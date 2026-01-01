# LDAP Secrets Engine Lab

Single-node Vault Enterprise cluster with OpenLDAP for troubleshooting Vault's LDAP secrets engine.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           AWS VPC                                │
│                        (10.1.0.0/16)                            │
│                                                                  │
│   ┌───────────────────┐         ┌───────────────────────────┐   │
│   │   Vault (t3.micro)│         │   OpenLDAP (t3.micro)     │   │
│   │                   │         │                           │   │
│   │ - Vault Enterprise│  ───►   │ - OpenLDAP (Docker)       │   │
│   │ - KMS auto-unseal │  :389   │ - phpLDAPadmin (:8080)    │   │
│   │ - Debug logging   │  :636   │ - Pre-seeded users        │   │
│   │ - tcpdump         │         │ - tcpdump                 │   │
│   └───────────────────┘         └───────────────────────────┘   │
│            │                                                     │
│            ▼                                                     │
│   ┌───────────────────┐                                         │
│   │    AWS KMS Key    │                                         │
│   │   (auto-unseal)   │                                         │
│   └───────────────────┘                                         │
└─────────────────────────────────────────────────────────────────┘
```

## Pre-seeded LDAP Directory

The OpenLDAP server comes pre-populated with:

| Type | DN | Password | Purpose |
|------|-----|----------|---------|
| Admin | `cn=admin,dc=vaultlab,dc=local` | admin123 | LDAP admin |
| User | `uid=alice,ou=people,...` | alice123 | Test user |
| User | `uid=bob,ou=people,...` | bob123 | Test user |
| User | `uid=charlie,ou=people,...` | charlie123 | Test user (admin group) |
| Service | `uid=svc-app1,ou=services,...` | svc-app1-pass | Static role testing |
| Service | `uid=svc-app2,ou=services,...` | svc-app2-pass | Static role testing |

Groups: `developers`, `admins`, `service-accounts`, `all-users`

## Prerequisites

1. AWS credentials (via Doormat):
   ```bash
   export AWS_ACCESS_KEY_ID=...
   export AWS_SECRET_ACCESS_KEY=...
   export AWS_SESSION_TOKEN=...
   ```

2. Vault Enterprise license

3. Terraform >= 1.0.0

## Quick Start

1. **Configure variables:**
   ```bash
   cd ldap-secrets-lab
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your Vault license
   ```

2. **Deploy infrastructure:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   # Note: All scripts from scripts/ are automatically deployed to ~/scripts/ on the Vault instance
   ```

3. **SSH to Vault and initialize:**
   ```bash
   # Use the SSH command from terraform output
   ssh -i ldaplab-key.pem ec2-user@<vault-ip>

   # Initialize Vault
   vault operator init

   # Save the root token and unseal keys!
   export VAULT_TOKEN=<root-token>
   ```

4. **Configure LDAP secrets engine:**
   ```bash
   # On the Vault instance (scripts are auto-deployed to ~/scripts/)
   ./scripts/configure-ldap-secrets.sh
   ```

5. **Access phpLDAPadmin:**
   ```
   URL: http://<ldap-public-ip>:8080
   Login DN: cn=admin,dc=vaultlab,dc=local
   Password: admin123
   ```

## Test Scenarios

Run from the Vault instance after initialization (scripts are in `~/scripts/`):

```bash
# Test static role password rotation
./scripts/test-static-role.sh

# Test dynamic credential generation
./scripts/test-dynamic-role.sh

# Test service account check-out/check-in
./scripts/test-library-set.sh
```

## Troubleshooting Tools

### On Vault Instance

```bash
# Run comprehensive diagnostics
./scripts/troubleshoot-ldap.sh

# Capture LDAP traffic
./scripts/capture-ldap-traffic.sh eth0 /tmp/ldap.pcap 60

# Check Vault logs
sudo journalctl -u vault -f

# Test LDAP connection manually
ldapsearch -x -H ldap://$LDAP_HOST:389 -D "cn=admin,$LDAP_BASE_DN" -w admin123 -b "$LDAP_BASE_DN"
```

### On LDAP Instance

```bash
# Check LDAP container status
./ldap-status.sh

# Search LDAP directory
./ldap-search.sh "(objectClass=inetOrgPerson)" "uid cn mail"

# Add a new test user
./ldap-add-user.sh testuser password123 Test User

# View OpenLDAP logs
docker logs -f openldap
```

## Common LDAP Secrets Engine Issues

### 1. Connection Failures
```bash
# Check network connectivity
nc -zv $LDAP_HOST 389

# Test with ldapsearch
ldapsearch -x -H ldap://$LDAP_HOST:389 -b "" -s base
```

### 2. Bind Credential Issues
```bash
# Test bind credentials
ldapwhoami -x -H ldap://$LDAP_HOST:389 -D "cn=admin,dc=vaultlab,dc=local" -w admin123
```

### 3. Schema Discovery Problems
```bash
# Check supported mechanisms
ldapsearch -x -H ldap://$LDAP_HOST:389 -b "" -s base supportedSASLMechanisms
```

### 4. Password Rotation Failures
```bash
# Enable Vault debug logging (already enabled)
# Check audit logs
vault audit enable file file_path=/var/log/vault/audit.log
```

## Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `vault_version` | `1.20.2+ent` | Vault Enterprise version |
| `vault_license` | (required) | Vault Enterprise license |
| `ldap_admin_password` | `admin123` | OpenLDAP admin password |
| `ldap_domain` | `vaultlab.local` | LDAP domain |
| `enable_ldap_tls` | `false` | Enable LDAPS (TLS) |

## Cleanup

```bash
# Destroy AWS resources
terraform destroy

# Remove local generated files
./cleanup.sh
```

## TLS Configuration

To test with LDAPS (TLS enabled):

1. Set `enable_ldap_tls = true` in terraform.tfvars
2. Re-apply: `terraform apply`
3. Configure Vault to use LDAPS:
   ```bash
   vault write ldap/config \
       url="ldaps://$LDAP_HOST:636" \
       insecure_tls=true \
       ...
   ```

## Files Structure

```
ldap-secrets-lab/
├── main.tf                 # Provider and SSH key
├── variables.tf            # Input variables
├── vpc.tf                  # VPC, subnets, routing
├── security_groups.tf      # Security groups
├── kms.tf                  # KMS key for auto-unseal
├── iam.tf                  # IAM roles for Vault
├── ec2.tf                  # Vault and LDAP instances
├── outputs.tf              # Output values
├── templates/
│   ├── vault-user-data.sh  # Vault instance setup
│   └── ldap-user-data.sh   # OpenLDAP instance setup
├── scripts/                      # Auto-deployed to ~/scripts/ on Vault instance
│   ├── configure-ldap-secrets.sh # Configure LDAP secrets engine
│   ├── test-static-role.sh       # Static role test
│   ├── test-dynamic-role.sh      # Dynamic role test
│   ├── test-library-set.sh       # Library set test
│   ├── troubleshoot-ldap.sh      # Diagnostics
│   └── capture-ldap-traffic.sh   # Packet capture
├── terraform.tfvars.example
├── cleanup.sh
└── README.md
```
