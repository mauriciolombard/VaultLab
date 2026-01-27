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

## How It Works

When a user runs `vault login -method=ldap username=alice`:

1. **Vault binds to OpenLDAP** using the admin account (`cn=admin,dc=vaultlab,dc=local`)
2. **Searches for the user** in `ou=users,dc=vaultlab,dc=local` by `uid` attribute
3. **Verifies password** by attempting to bind as the user's full DN
4. **Queries group membership** using filter `(member={{.UserDN}})`
5. **Maps LDAP groups to Vault policies** (e.g., `vault-admins` → `ldap-admins` policy)
6. **Returns a token** with the mapped policies attached

For detailed authentication flow diagrams and OpenLDAP-specific configuration, see [docs/ldap-auth-flow.md](docs/ldap-auth-flow.md).

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
terraform apply -auto-approve
```

### 5. Test LDAP Connectivity

**Note:** If LDAP is restricted to VPC-only (`allowed_ldap_cidrs = []`), you must test from a Vault node:

```bash
# SSH into a Vault node
cd ../awskms-autounseal
$(terraform output -json ssh_connection_commands | jq -r '.vault1')

# Install connectivity tools (one-time)
sudo yum install -y openldap-clients telnet nmap-ncat

# Quick port connectivity test (use telnet or nc)
nc -zv <LDAP_PRIVATE_IP> 389
# or
telnet <LDAP_PRIVATE_IP> 389

# Test LDAP query
ldapsearch -x -H ldap://<LDAP_PRIVATE_IP>:389 -b "dc=vaultlab,dc=local" "(objectClass=*)" dn
```

**Note:** Replace `<LDAP_PRIVATE_IP>` with `terraform output -raw ldap_server_private_ip` from `ldap-auth-openldap/`.


### 6. Test Vault LDAP Login

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

**Admin/Bind Account:** `cn=admin,dc=vaultlab,dc=local` (Password: `admin123`)

## Utility Scripts

### `scripts/test-ldap.sh` (LDAP Connectivity)
Comprehensive test suite for validating OpenLDAP connectivity and directory structure.

```bash
./scripts/test-ldap.sh $(terraform output -raw ldap_server_public_ip)
```

Tests include: anonymous bind, admin bind, user listing, group listing, user authentication (alice/bob), and group membership queries.

### `scripts/test-vault-auth.sh` (Vault Authentication)
Validates Vault LDAP authentication end-to-end.

```bash
export VAULT_ADDR="http://<NLB_ADDRESS>:8200"
./scripts/test-vault-auth.sh
```

Tests include: auth method verification, user logins (alice/bob), policy enforcement, wrong password rejection, and group mapping verification.

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

## Key Differences from Active Directory

| Aspect | OpenLDAP | Active Directory |
|--------|----------|------------------|
| User attribute | `uid` | `sAMAccountName` |
| Bind format | Full DN (`uid=alice,ou=users,...`) | UPN (`user@domain`) |
| User container | `ou=users,dc=...` | `CN=Users,DC=...` |
| Group filter | Simple member filter `(member={{.UserDN}})` | Uses OID for nested groups |
| Admin account | `cn=admin,dc=...` | Service account UPN |
| Group names | Lowercase convention (`vault-admins`) | PascalCase (`Vault-Admins`) |
| Setup time | ~2 minutes | 10-15 minutes (AD DS promotion) |

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

### Common Issues

1. **LDAP not accessible** - Check if `allowed_ldap_cidrs` includes your IP, or test from within VPC
2. **Wrong userattr** - Must be `uid` for OpenLDAP (not `sAMAccountName`)
3. **Bind DN format** - OpenLDAP uses full DN (`cn=admin,dc=...`), not UPN format
4. **Group not mapping** - Ensure group names match exactly (case-sensitive: `vault-admins`)

## Cleanup

```bash
terraform destroy -auto-approve
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
