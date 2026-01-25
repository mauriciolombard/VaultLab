# Active Directory Authentication for Vault

> **Prerequisite:** This integration requires the Vault cluster from `awskms-autounseal/` to be deployed and running in AWS before proceeding.

This Terraform configuration deploys a Windows Server 2022 EC2 instance with Active Directory Domain Services (AD DS) and configures Vault LDAP authentication. It integrates with an existing Vault cluster (from `awskms-autounseal/`).

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
│  │              │ Windows Server  │                    │    │
│  │              │  2022 with AD   │                    │    │
│  │              │  Domain Services│                    │    │
│  │              └─────────────────┘                    │    │
│  │                                                      │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## How It Works

When a user runs `vault login -method=ldap username=alice`:

1. **Vault binds to AD** using the service account (`vault-svc@vaultlab.local`)
2. **Searches for the user** in `CN=Users,DC=vaultlab,DC=local` by `sAMAccountName`
3. **Verifies password** by attempting to bind as the user
4. **Queries group membership** using AD's nested group OID (`1.2.840.113556.1.4.1941`)
5. **Maps AD groups to Vault policies** (e.g., `Vault-Admins` → `ldap-admins` policy)
6. **Returns a token** with the mapped policies attached

For detailed authentication flow diagrams and AD-specific configuration, see [docs/ad-auth-flow.md](docs/ad-auth-flow.md).

## Prerequisites

1. **Vault cluster deployed** via `awskms-autounseal/`
2. **AWS credentials** configured (via Doormat)
3. **Terraform** >= 1.0.0
4. **Vault CLI** installed
5. **ldapsearch** utility (for testing from Linux/Mac)
6. **RDP client** (for Windows server access)

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
cd ../ldap-auth-ad
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
aws_region   = "us-east-1"
vpc_id       = "vpc-xxxxxxxxx"       # From Vault cluster VPC
vault_addr   = "http://nlb-xxx:8200" # From Vault outputs
vault_token  = "hvs.xxxxx"           # Root or admin token
```

### 4. Deploy Windows AD Server

```bash
terraform init
terraform apply -auto-approve
```

**IMPORTANT:** Windows AD setup takes **10-15 minutes** after EC2 launch. The server will:
1. Install AD DS and DNS roles
2. Promote itself to a Domain Controller
3. Restart automatically
4. Create test users and groups after restart

### 5. Test LDAP from Vault Server

LDAP port 389 is only accessible from within the VPC. SSH into a Vault node to test:

```bash
# Get the SSH command for vault1
cd ../awskms-autounseal
$(terraform output -json ssh_connection_commands | jq -r '.vault1')
```

Once on the Vault server:

```bash
# Install ldapsearch (one-time)
sudo yum install -y openldap-clients

# Test service account bind
ldapsearch -x -H ldap://10.0.1.49:389 \
  -D 'vault-svc@vaultlab.local' -w 'VaultBind123!' \
  -b 'DC=vaultlab,DC=local' '(sAMAccountName=alice)' sAMAccountName memberOf

# Test alice user bind
ldapsearch -x -H ldap://10.0.1.49:389 \
  -D 'alice@vaultlab.local' -w 'Password123!' \
  -b '' -s base namingContexts

# List all users
ldapsearch -x -H ldap://10.0.1.49:389 \
  -D 'vault-svc@vaultlab.local' -w 'VaultBind123!' \
  -b 'CN=Users,DC=vaultlab,DC=local' '(objectClass=user)' sAMAccountName
```

**Note:** Replace `10.0.1.49` with `$(terraform output -raw ad_server_private_ip)` from `ldap-auth-ad/`. Use single quotes around passwords containing `!` to avoid shell interpretation.

### 6. Test Vault LDAP Login

From anywhere (your local machine works):
```bash
vault login -method=ldap username=alice password=Password123!
vault token lookup  # Should show ldap-admins policy
```

## Test Users

| Username | Password | AD Group | Vault Policy |
|----------|----------|----------|--------------|
| alice | Password123! | Vault-Admins | ldap-admins (full access) |
| bob | Password123! | Vault-Users | ldap-users (read-only) |
| charlie | Password123! | Vault-Users | ldap-users (read-only) |

**Service Account:** `vault-svc@vaultlab.local` (Password: `VaultBind123!`)

## Directory Structure

```
ldap-auth-ad/
├── main.tf                 # Provider configuration
├── variables.tf            # Input variables
├── terraform.tfvars.example
├── ec2-windows-ad.tf       # Windows Server EC2 instance
├── security_groups.tf      # Security groups (AD ports)
├── outputs.tf              # Terraform outputs
├── vault-ldap-auth.tf      # Vault LDAP auth configuration (AD-specific)
├── templates/
│   └── ad-user-data.ps1    # PowerShell script for AD setup
├── scripts/
│   ├── create-ad-users.ps1 # Manual user creation script (run on AD server)
│   └── test-vault-auth.sh  # Vault LDAP auth tests
└── docs/
    ├── ad-auth-flow.md     # Authentication flow diagram
    └── troubleshooting.md  # Common issues and solutions
```

## Key Differences from OpenLDAP

| Aspect | Active Directory | OpenLDAP |
|--------|-----------------|----------|
| User attribute | `sAMAccountName` | `uid` |
| Bind format | `user@domain` (UPN) | Full DN |
| User container | `CN=Users,DC=...` | `ou=users,dc=...` |
| Group filter | Uses OID for nested groups | Simple member filter |
| Group names | **Case-sensitive in Vault!** | Case-sensitive |

## RDP Access

```bash
# Get connection info
terraform output rdp_connection_info

# Get password
terraform output -raw windows_admin_password
```

Connect using any RDP client:
- **Host:** `<public_ip>:3389`
- **Username:** `Administrator`
- **Password:** From terraform output

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for common issues.

### Quick Checks

```bash
# Test Vault LDAP login (works from anywhere)
vault login -method=ldap username=alice password=Password123!

# Check Vault LDAP config
vault read auth/ldap/config

# List LDAP group mappings (case-sensitive!)
vault list auth/ldap/groups
```

**Note:** Direct LDAP testing (ldapsearch) must be run from a Vault node inside the VPC. See [Step 5](#5-test-ldap-from-vault-server) above.

### Common Issues

1. **AD not ready** - Wait 10-15 minutes after deploy
2. **Wrong userattr** - Must be `sAMAccountName` for AD
3. **Group case mismatch** - Vault group names must match AD exactly (e.g., `Vault-Admins` not `vault-admins`)

## Cleanup

```bash
terraform destroy -auto-approve
```

This removes:
- Windows Server EC2 instance
- Security groups
- Key pair
- Vault LDAP auth configuration (if `configure_vault_ldap = true`)

The Vault cluster (`awskms-autounseal/`) remains intact.

## Documentation

- [AD Authentication Flow](docs/ad-auth-flow.md) - Detailed auth flow diagram and AD-specific config
- [Troubleshooting Guide](docs/troubleshooting.md) - Common issues and solutions

