#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log) 2>&1
echo "Starting PostgreSQL installation at $(date)"

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# Install PostgreSQL (Ubuntu 24.04 ships PostgreSQL 16 in its default repos)
apt-get install -y postgresql postgresql-contrib

# PostgreSQL is auto-initialized and started on Ubuntu after install
# Config paths on Ubuntu: /etc/postgresql/<version>/main/
PG_VERSION=$(pg_lsclusters -h | awk '{print $1}' | head -1)
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"

# Backup original configs
cp $PG_HBA $PG_HBA.bak
cp $PG_CONF $PG_CONF.bak

# Configure PostgreSQL to listen on all interfaces
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $PG_CONF

# Configure authentication (allow scram-sha-256 from any IP - for lab only)
cat > $PG_HBA << 'EOF'
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/0                    scram-sha-256
EOF

# Restart PostgreSQL to pick up config changes
systemctl restart postgresql

# Wait for PostgreSQL to be ready
sleep 5

# Create vault_admin user and database
sudo -u postgres psql << EOF
-- Create the vault admin user
CREATE USER vault_admin WITH PASSWORD '${postgres_password}' SUPERUSER CREATEROLE CREATEDB;

-- Create the database
CREATE DATABASE ${postgres_db_name} OWNER vault_admin;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE ${postgres_db_name} TO vault_admin;

-- Connect to the new database and set up schema permissions
\c ${postgres_db_name}
GRANT ALL ON SCHEMA public TO vault_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO vault_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO vault_admin;

-- Create a test table for verifying credentials
CREATE TABLE IF NOT EXISTS test_data (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO test_data (name) VALUES ('test_record_1'), ('test_record_2'), ('test_record_3');

GRANT SELECT ON test_data TO PUBLIC;
EOF

echo "PostgreSQL setup completed at $(date)"
echo "Database: ${postgres_db_name}"
echo "Admin user: vault_admin"
