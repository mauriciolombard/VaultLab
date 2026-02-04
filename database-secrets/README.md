# Database Secrets Engine Integrations

> **Prerequisite:** This integration requires the Vault cluster from `awskms-autounseal/` to be deployed and running in AWS before proceeding.

This folder contains isolated database integrations for testing Vault's database secrets engine. Each subfolder deploys a single database type on its own EC2 instance.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Existing Vault Cluster (NLB)                │
│                        awskms-autounseal/                       │
└───────────────┬─────────────┬─────────────┬─────────────┘
                │             │             │
        ┌───────▼───┐   ┌─────▼─────┐   ┌───▼───┐
        │PostgreSQL │   │   MySQL   │   │MongoDB│
        │ t3.micro  │   │ t3.micro  │   │t3.small│
        │   :5432   │   │   :3306   │   │ :27017│
        └───────────┘   └───────────┘   └───────┘
              ▲               ▲              ▲
              │               │              │
    terraform apply     terraform apply  (each is independent)
```

## Available Database Integrations

| Folder | Database | Vault Plugin | Port | Instance | Use Case |
|--------|----------|--------------|------|----------|----------|
| `postgresql/` | PostgreSQL | `postgresql-database-plugin` | 5432 | t3.micro | SQL reference, most common |
| `mysql/` | MySQL 8 | `mysql-database-plugin` | 3306 | t3.micro | MySQL family (covers MariaDB) |
| `mongodb/` | MongoDB | `mongodb-database-plugin` | 27017 | t3.small | NoSQL document |

## Quick Start

Each database integration is self-contained. Deploy only what you need:

```bash
# Set AWS credentials (via Doormat)
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...

# Get Vault cluster info
cd ../awskms-autounseal
terraform output vault_addr
terraform output -raw vpc_id

# Deploy a specific database (e.g., PostgreSQL)
cd ../database-secrets/postgresql
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with vpc_id, vault_addr, vault_token
terraform init
terraform apply -auto-approve

# This creates:
# - Database EC2 instance with security groups
# - Vault database mount at database/<db>/
# - Connection + roles configured via vault-db-config.tf
# Vault roles: readonly, readwrite, admin
```

## Testing Dynamic Credentials

### Step 1: Generate Credentials (from your local CLI)

You can generate credentials from anywhere that can reach the Vault cluster:

```bash
# From your local machine (with VAULT_ADDR and VAULT_TOKEN set)
vault read database/postgresql/creds/readonly

# Example output:
# Key                Value
# ---                -----
# lease_id           database/postgresql/creds/readonly/1QNpl5lTi2zjR77JFQQcrjip
# lease_duration     1h
# lease_renewable    true
# password           XLTCO5-5aBLDmU0AvC9u
# username           v-root-readonly-12JQj9CC86f4AwjmKtbZ-1770071552
```

### Step 2: Use Credentials (from database EC2 instance)

To actually connect to the database with the generated credentials, SSH into the database EC2 instance (the database is only accessible within the VPC):

```bash
# Get SSH command
terraform output ssh_connection_command

# SSH to the database instance
ssh -i <db>-key.pem ec2-user@<PUBLIC_IP>

# Connect using the credentials from Step 1
# PostgreSQL:
psql -h localhost -U <generated-username> -d vaultdb -c 'SELECT version();'
psql -h localhost -U <generated-username> -d vaultdb -c 'SELECT current_user, current_database();'
psql -h localhost -U <generated-username> -d vaultdb -c 'SELECT usename FROM pg_user;'

# MySQL:
mysql -u <generated-username> -p<generated-password> -e 'SELECT version();'
mysql -u <generated-username> -p<generated-password> -e 'SELECT current_user(), database();'
mysql -u <generated-username> -p<generated-password> -e 'SELECT user, host FROM mysql.user;'

# MongoDB:
mongosh -u <generated-username> -p <generated-password> --authenticationDatabase admin --eval 'db.runCommand({connectionStatus: 1})'
mongosh -u <generated-username> -p <generated-password> --authenticationDatabase admin --eval 'db.getSiblingDB("vaultdb").test_data.find()'
mongosh -u <generated-username> -p <generated-password> --authenticationDatabase admin
```

### Optional: Test Admin Connectivity

To verify the database is running correctly with the admin account:

```bash
# Get admin password
terraform output -raw <db>_admin_password  # e.g., postgres_admin_password

# From the database EC2 instance:
# PostgreSQL: psql -h 127.0.0.1 -U vault_admin -d vaultdb -c 'SELECT version();'
# MySQL:      mysql -u vault_admin -p -e 'SELECT version();'
# MongoDB:    mongosh --eval 'db.version()'
```

## Cleanup

**Important:** Revoke active leases before destroying to avoid errors:

```bash
cd database-secrets/postgresql

# Run the revoke command
vault lease revoke -force -prefix database/postgresql/

# Now safe to destroy
terraform destroy -auto-approve
# Removes: PostgreSQL EC2 + database mount from Vault
# Preserves: The entire Vault cluster from awskms-autounseal/
```

See [Troubleshooting - Section 7](docs/troubleshooting.md#section-7-terraform-destroy-issues) if destroy fails with lease errors.

## Documentation

- [Database Secrets Flow](docs/database-secrets-flow.md) - How Vault's credential lifecycle works (all databases)
- [Troubleshooting](docs/troubleshooting.md) - Common issues and decision trees (all databases)

For database-specific configuration details, refer to the [official Vault documentation](https://developer.hashicorp.com/vault/docs/secrets/databases).

## Folder Structure

```
database-secrets/
├── README.md                 # This file
├── postgresql/               # PostgreSQL integration
├── mysql/                    # MySQL integration
├── mongodb/                  # MongoDB integration
└── docs/
    ├── database-secrets-flow.md    # Common credential lifecycle
    └── troubleshooting.md          # Common troubleshooting
```
