#!/bin/bash
# Note: Removed set -e for better error visibility in logs

# Log all output
exec > >(tee /var/log/user-data.log) 2>&1
echo "Starting MariaDB installation at $(date)"

# Update system
echo "Running dnf update..."
dnf update -y

# Install MariaDB (MySQL-compatible, available in AL2023 repos)
echo "Installing MariaDB..."
if ! dnf install -y mariadb105-server mariadb105; then
  echo "ERROR: Failed to install MariaDB packages"
  exit 1
fi

# Start MariaDB service
echo "Starting MariaDB service..."
systemctl enable mariadb
if ! systemctl start mariadb; then
  echo "ERROR: Failed to start mariadb service"
  systemctl status mariadb
  exit 1
fi

# Wait for MariaDB to be ready (up to 2 minutes)
echo "Waiting for MariaDB to accept connections..."
for i in {1..24}; do
  if mysqladmin ping -h localhost --silent 2>/dev/null; then
    echo "MariaDB is ready!"
    break
  fi
  if [ $i -eq 24 ]; then
    echo "ERROR: MariaDB failed to accept connections after 2 minutes"
    systemctl status mariadb
    journalctl -u mariadb --no-pager | tail -30
    exit 1
  fi
  echo "Waiting... attempt $i/24"
  sleep 5
done

# Secure MariaDB installation and set up vault_admin user
mysql << EOF
-- Set root password
ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysql_root_password}';

-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Remove remote root login
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Remove test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Create vault_admin user for Vault to manage dynamic credentials
CREATE USER 'vault_admin'@'%' IDENTIFIED BY '${mysql_root_password}';
GRANT ALL PRIVILEGES ON *.* TO 'vault_admin'@'%' WITH GRANT OPTION;
GRANT CREATE USER ON *.* TO 'vault_admin'@'%';

-- Create the application database
CREATE DATABASE IF NOT EXISTS ${mysql_db_name};

-- Create a test table for verifying credentials
USE ${mysql_db_name};
CREATE TABLE IF NOT EXISTS test_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO test_data (name) VALUES ('test_record_1'), ('test_record_2'), ('test_record_3');

-- Flush privileges
FLUSH PRIVILEGES;
EOF

echo "MariaDB setup completed at $(date)"
echo "Database: ${mysql_db_name}"
echo "Admin user: vault_admin"
