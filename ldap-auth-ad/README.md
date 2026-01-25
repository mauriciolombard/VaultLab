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
terraform apply
```

**IMPORTANT:** Windows AD setup takes **10-15 minutes** after EC2 launch. The server will:
1. Install AD DS and DNS roles
2. Promote itself to a Domain Controller
3. Restart automatically
4. Create test users and groups after restart

### 5. Wait for AD to be Ready

Check the setup progress:
```bash
# Get Windows admin password
terraform output -raw windows_admin_password

# RDP to the server
terraform output rdp_connection_info
```

Via RDP, check `C:\AD-Setup.log` or run:
```powershell
Get-ADDomain
Get-ADUser -Filter * | Select-Object SamAccountName
```

### 6. Test AD LDAP Connectivity

```bash
chmod +x scripts/*.sh
./scripts/test-ad.sh $(terraform output -raw ad_server_public_ip)
```

### 7. Test Vault LDAP Login

```bash
export VAULT_ADDR=$(cd ../awskms-autounseal && terraform output -raw vault_addr)
./scripts/test-vault-auth.sh
```

Or manually:
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
│   ├── create-ad-users.ps1 # Manual user creation script
│   ├── test-ad.sh          # LDAP connectivity tests
│   └── test-vault-auth.sh  # Vault auth tests
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
# Test LDAP connectivity
ldapsearch -x -H ldap://$(terraform output -raw ad_server_public_ip):389 \
    -D "vault-svc@vaultlab.local" \
    -w "VaultBind123!" \
    -b "DC=vaultlab,DC=local" \
    "(sAMAccountName=alice)" dn

# Check Vault LDAP config
vault read auth/ldap/config

# List LDAP group mappings (case-sensitive!)
vault list auth/ldap/groups
```

### Common Issues

1. **AD not ready** - Wait 10-15 minutes after deploy
2. **Wrong userattr** - Must be `sAMAccountName` for AD
3. **Group case mismatch** - Vault group names must match AD exactly (e.g., `Vault-Admins` not `vault-admins`)

## Cleanup

```bash
terraform destroy
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

## Cost Considerations

- **Instance type:** t3.medium (~$0.0416/hour)
- Windows Server 2022 includes license in EC2 pricing
- **Estimated cost:** ~$30/month if running 24/7
- **Tip:** Destroy when not in use to minimize costs
