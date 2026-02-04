#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log) 2>&1
echo "Starting MongoDB installation at $(date)"

# Update system
dnf update -y

# Add MongoDB repository
cat > /etc/yum.repos.d/mongodb-org-7.0.repo << 'EOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2023/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-7.0.asc
EOF

# Install MongoDB
dnf install -y mongodb-org

# Ensure MongoDB data directory has correct ownership
chown -R mongod:mongod /var/lib/mongo
chown -R mongod:mongod /var/log/mongodb

# Configure MongoDB
MONGO_CONF="/etc/mongod.conf"

# Backup original config
cp $MONGO_CONF $MONGO_CONF.bak

# Configure MongoDB to listen on all interfaces and enable auth
cat > $MONGO_CONF << 'EOF'
# mongod.conf

# Where to write logging data
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

# Where and how to store data
storage:
  dbPath: /var/lib/mongo

# Network interfaces
net:
  port: 27017
  bindIp: 0.0.0.0

# Process Management
processManagement:
  timeZoneInfo: /usr/share/zoneinfo

# Security
security:
  authorization: enabled
EOF

# Start MongoDB without auth first to create admin user
cat > /tmp/mongod-noauth.conf << 'EOF'
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
storage:
  dbPath: /var/lib/mongo
net:
  port: 27017
  bindIp: 0.0.0.0
processManagement:
  timeZoneInfo: /usr/share/zoneinfo
EOF

# Start MongoDB without auth as mongod user
runuser -u mongod -- mongod --config /tmp/mongod-noauth.conf --fork

# Wait for MongoDB to be ready
sleep 10

# Create admin user and vault_admin user
mongosh admin << EOF
// Create root admin user
db.createUser({
  user: "admin",
  pwd: "${mongodb_admin_password}",
  roles: [{ role: "root", db: "admin" }]
});

// Create vault_admin user for Vault to manage dynamic credentials
db.createUser({
  user: "vault_admin",
  pwd: "${mongodb_admin_password}",
  roles: [
    { role: "root", db: "admin" }
  ]
});

// Switch to the application database
use ${mongodb_db_name}

// Create a test collection
db.test_data.insertMany([
  { name: "test_record_1", created_at: new Date() },
  { name: "test_record_2", created_at: new Date() },
  { name: "test_record_3", created_at: new Date() }
]);
EOF

# Stop MongoDB running without auth (as mongod user)
runuser -u mongod -- mongod --shutdown --dbpath /var/lib/mongo

# Wait for clean shutdown
sleep 5

# Start MongoDB with auth enabled via systemd
systemctl enable mongod
systemctl start mongod

# Wait for MongoDB to be ready
sleep 5

# Verify connection with authentication
mongosh "mongodb://vault_admin:${mongodb_admin_password}@localhost:27017/admin" --eval "db.adminCommand('ping')"

echo "MongoDB setup completed at $(date)"
echo "Database: ${mongodb_db_name}"
echo "Admin user: vault_admin"
echo "Authentication: enabled"
