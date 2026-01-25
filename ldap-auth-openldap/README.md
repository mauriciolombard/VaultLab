# OpenLDAP Authentication for Vault

> **Prerequisite:** This integration requires the Vault cluster from `awskms-autounseal/` to be deployed and running in AWS before proceeding.

This Terraform configuration deploys an OpenLDAP server and configures Vault LDAP authentication. It integrates with an existing Vault cluster (from `awskms-autounseal/`).

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS VPC                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                                                      │    │
│  │   ┌─────────┐    ┌─────────┐    ┌─────────┐        │    │
│  │   │ Vault 1 │    │ Vault 2 │    │ Vault 3 │        │    │
│  │   └────┬────┘    └────┬────┘    └────┬────┘        │    │
│  │        │              │              │              │    │
│  │        └──────────────┼──────────────┘              │    │
│  │                       │                             │    │
│  │                       │ LDAP Auth                   │    │
│  │                       │ (port 389)                  │    │
│  │                       ▼                             │    │
│  │              ┌─────────────────┐                    │    │
│  │              │    OpenLDAP     │                    │    │
│  │              │     Server      │                    │    │
│  │              └─────────────────┘                    │    │
│  │                                                      │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **Vault cluster deployed** via `awskms-autounseal/`
2. **AWS credentials** configured (via Doormat)
3. **Terraform** >= 1.0.0
4. **Vault CLI** installed
5. **ldapsearch** utility (for testing)

## Quick Start

### 1. Set AWS Credentials

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
```

### 2. Get Vault Cluster Info

From the `awskms-autounseal/` directory:
```bash
cd ../awskms-autounseal
terraform output vault_addr       # Copy this
terraform output -raw vpc_id      # If available, or get from AWS console
```

### 3. Configure Variables

```bash
cd ../ldap-auth-openldap
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
aws_region   = "us-east-1"
vpc_id       = "vpc-xxxxxxxxx"       # From Vault cluster VPC
vault_addr   = "http://nlb-xxx:8200" # From Vault outputs
vault_token  = "hvs.xxxxx"           # Root or admin token
```

### 4. Deploy OpenLDAP

```bash
terraform init
terraform apply
```

### 5. Test LDAP Connectivity

```bash
chmod +x scripts/*.sh
./scripts/test-ldap.sh $(terraform output -raw ldap_server_public_ip)
```

### 6. Test Vault LDAP Login

```bash
export VAULT_ADDR=$(terraform output -raw vault_addr 2>/dev/null || echo "http://your-vault:8200")
./scripts/test-vault-auth.sh
```

Or manually:
```bash
vault login -method=ldap username=alice password=password123
vault token lookup  # Should show ldap-admins policy
```

## Test Users

| Username | Password | LDAP Group | Vault Policy |
|----------|----------|------------|--------------|
| alice | password123 | vault-admins | ldap-admins (full access) |
| bob | password123 | vault-users | ldap-users (read-only) |
| charlie | password123 | vault-users | ldap-users (read-only) |

## Directory Structure

```
ldap-auth-openldap/
├── main.tf                 # Provider configuration
├── variables.tf            # Input variables
├── terraform.tfvars.example
├── ec2-openldap.tf         # OpenLDAP EC2 instance
├── security_groups.tf      # Security groups
├── outputs.tf              # Terraform outputs
├── vault-ldap-auth.tf      # Vault LDAP auth configuration
├── templates/
│   └── openldap-user-data.sh   # EC2 bootstrap script
├── ldif/
│   ├── base.ldif           # Base directory structure (reference)
│   └── test-users.ldif     # Test users/groups (reference)
├── scripts/
│   ├── test-ldap.sh        # LDAP connectivity tests
│   └── test-vault-auth.sh  # Vault auth tests
├── vault-policies/
│   └── ldap-policy.hcl     # Admin policy for vault-admins
└── docs/
    ├── ldap-auth-flow.md   # Authentication flow diagram
    └── troubleshooting.md  # Common issues and solutions
```

## Outputs

After deployment, run `terraform output` to see:
- `ldap_server_public_ip` - SSH access
- `ldap_server_private_ip` - For Vault configuration
- `ldap_url` - LDAP URL for Vault
- `ssh_connection_command` - SSH command
- `test_ldapsearch_command` - ldapsearch test command
- `vault_ldap_login_alice` - Vault login command

## SSH Access

```bash
ssh -i ldap-key.pem ec2-user@$(terraform output -raw ldap_server_public_ip)
```

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for common issues.

### Quick Checks

```bash
# Test LDAP connectivity
ldapsearch -x -H ldap://$(terraform output -raw ldap_server_public_ip):389 \
  -b "dc=vaultlab,dc=local" "(objectClass=*)" dn

# Check Vault LDAP config
vault read auth/ldap/config

# List LDAP group mappings
vault list auth/ldap/groups
```

## Cleanup

```bash
terraform destroy
```

This removes:
- OpenLDAP EC2 instance
- Security groups
- SSH key pair
- Vault LDAP auth configuration (if `configure_vault_ldap = true`)

The Vault cluster (`awskms-autounseal/`) remains intact.

## Documentation

- [LDAP Authentication Flow](docs/ldap-auth-flow.md) - Detailed auth flow diagram
- [Troubleshooting Guide](docs/troubleshooting.md) - Common issues and solutions
