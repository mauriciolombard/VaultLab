#!/bin/bash
set -ex

# Variables from Terraform
VAULT_VERSION="${vault_version}"
VAULT_LICENSE="${vault_license}"
KMS_KEY_ID="${kms_key_id}"
AWS_REGION="${aws_region}"
LDAP_HOST="${ldap_host}"
LDAP_BASE_DN="${ldap_base_dn}"

# Get instance metadata
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

# Install dependencies
dnf install -y yum-utils jq tcpdump openldap-clients

# Add HashiCorp repo and install Vault Enterprise
dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
dnf install -y vault-enterprise-$${VAULT_VERSION}

# Create Vault data directory
mkdir -p /opt/vault/data
chown -R vault:vault /opt/vault

# Write Vault license
cat > /etc/vault.d/vault.hclic <<EOF
$${VAULT_LICENSE}
EOF
chmod 640 /etc/vault.d/vault.hclic
chown vault:vault /etc/vault.d/vault.hclic

# Create Vault configuration
cat > /etc/vault.d/vault.hcl <<EOF
ui = true
log_level = "debug"

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault1"
}

disable_mlock = true

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = true
}

seal "awskms" {
  region     = "$${AWS_REGION}"
  kms_key_id = "$${KMS_KEY_ID}"
}

api_addr     = "http://$${PRIVATE_IP}:8200"
cluster_addr = "http://$${PRIVATE_IP}:8201"

license_path = "/etc/vault.d/vault.hclic"
EOF

chmod 640 /etc/vault.d/vault.hcl
chown vault:vault /etc/vault.d/vault.hcl

# Set VAULT_ADDR for all users on login
cat > /etc/profile.d/vault.sh <<EOF
export VAULT_ADDR=http://127.0.0.1:8200
export LDAP_HOST=$${LDAP_HOST}
export LDAP_BASE_DN="$${LDAP_BASE_DN}"
EOF

# Create scripts directory for Terraform provisioner to deploy scripts
mkdir -p /home/ec2-user/scripts
chown ec2-user:ec2-user /home/ec2-user/scripts

# Create audit log directory
mkdir -p /var/log/vault
chown vault:vault /var/log/vault

# Enable and start Vault
systemctl enable vault
systemctl start vault

# Wait for Vault to be ready
sleep 10

# Log startup status
vault status || true
