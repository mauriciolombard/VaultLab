# Database Secrets Engine - Troubleshooting Guide

This guide covers common issues that apply to ALL database types when working with Vault's database secrets engine.

## Quick Diagnosis Decision Tree

```
Credential generation failing?
│
├─ Can Vault reach the database?
│  │
│  ├─ NO ──▶ [NETWORK ISSUES] See Section 1
│  │
│  └─ YES ─▶ Can Vault authenticate to database?
│            │
│            ├─ NO ──▶ [AUTH ISSUES] See Section 2
│            │
│            └─ YES ─▶ Does the role exist and match?
│                      │
│                      ├─ NO ──▶ [CONFIG ISSUES] See Section 3
│                      │
│                      └─ YES ─▶ Are creation statements valid?
│                                │
│                                ├─ NO ──▶ [STATEMENT ISSUES] See Section 4
│                                │
│                                └─ YES ─▶ [LEASE ISSUES] See Section 5
```

---

## Section 1: Network Connectivity Issues

### Symptoms
- `connection refused`
- `no route to host`
- `timeout`
- `dial tcp <IP>:<PORT>: i/o timeout`

### Diagnosis Steps

```bash
# 1. Test basic connectivity from Vault node
nc -zv <DB_HOST> <DB_PORT>
# or
telnet <DB_HOST> <DB_PORT>

# 2. Check security group rules
aws ec2 describe-security-groups --group-ids <SG_ID>

# 3. Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<VPC_ID>"

# 4. From Vault node, verify DNS resolution
nslookup <DB_HOST>
# or
dig <DB_HOST>
```

### Common Causes & Fixes

| Cause | Fix |
|-------|-----|
| Security group missing inbound rule | Add inbound rule for DB port from Vault SG |
| Database not listening on expected interface | Check DB config binds to `0.0.0.0` not `127.0.0.1` |
| VPC routing issue | Ensure both in same VPC or proper peering/routing |
| Database service not running | SSH to DB server, check service status |

### Security Group Check Pattern

```
┌─────────────────────────────────────────────────────────────┐
│                    REQUIRED CONNECTIVITY                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────┐         ┌────────────────┐              │
│  │  Vault Nodes   │ ──────▶ │   Database     │              │
│  │                │   DB    │                │              │
│  │  (SG: vault)   │  PORT   │  (SG: db-sg)   │              │
│  └────────────────┘         └────────────────┘              │
│                                                              │
│  DB Security Group MUST allow:                               │
│  - Inbound: <DB_PORT> from Vault Security Group              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Section 2: Authentication Issues

### Symptoms
- `authentication failed`
- `Access denied for user`
- `password authentication failed`
- `invalid credentials`

### Diagnosis Steps

```bash
# 1. Verify Vault has correct credentials stored
vault read database/<mount>/config/<name>
# Note: Password is redacted, but check username and connection_url

# 2. Test credentials directly (from Vault node)
# This confirms credentials work outside of Vault

# PostgreSQL:
PGPASSWORD='<password>' psql -h <host> -U <user> -d <db> -c "SELECT 1"

# MySQL:
mysql -h <host> -u <user> -p<password> -e "SELECT 1"

# MongoDB:
mongosh "mongodb://<user>:<password>@<host>:<port>/admin"

# 3. Check if credentials were rotated
# If root rotation was performed, original credentials no longer work
vault read database/<mount>/config/<name>
# Look for "root_rotation_statements" being set
```

### Common Causes & Fixes

| Cause | Fix |
|-------|-----|
| Wrong password in config | Re-write config with correct password |
| Root rotation performed | Use Vault-generated password (you won't know it) |
| Password contains special chars | URL-encode special characters in connection_url |
| User doesn't exist in database | Create the admin user in the database first |
| User lacks privileges | Grant CREATE USER / necessary privileges |

### Privilege Requirements

```
┌─────────────────────────────────────────────────────────────┐
│              MINIMUM PRIVILEGES FOR VAULT ADMIN              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  The admin user Vault uses MUST be able to:                  │
│                                                              │
│  1. CREATE new users/roles                                   │
│  2. SET passwords for those users                            │
│  3. GRANT permissions to those users                         │
│  4. DROP/DELETE those users (for revocation)                 │
│                                                              │
│  This typically means SUPERUSER or equivalent privileges.    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Section 3: Configuration Issues

### Symptoms
- `no database found`
- `role not found`
- `unknown database type`
- `connection not configured`

### Diagnosis Steps

```bash
# 1. List all configured connections
vault list database/config

# 2. Read specific connection (verify it exists)
vault read database/<mount>/config/<name>

# 3. List all roles
vault list database/<mount>/roles

# 4. Read specific role
vault read database/<mount>/roles/<role>

# 5. Verify role references correct connection
vault read database/<mount>/roles/<role>
# Check: db_name matches a connection name
```

### Common Causes & Fixes

| Cause | Fix |
|-------|-----|
| Role references wrong db_name | Update role with correct `db_name` value |
| allowed_roles doesn't include this role | Update connection config to include role |
| Mount path mismatch | Verify using correct mount path |
| Connection not configured | Write connection config first |

### Configuration Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                    CONFIGURATION ORDER                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. MOUNT the secrets engine                                 │
│     vault secrets enable -path=database/postgresql database  │
│                                                              │
│  2. CONFIGURE the connection                                 │
│     vault write database/postgresql/config/mydb ...          │
│     └── allowed_roles=["readonly", "readwrite"]              │
│                                                              │
│  3. CREATE roles that reference the connection               │
│     vault write database/postgresql/roles/readonly ...       │
│     └── db_name="mydb"  <── must match config name           │
│                                                              │
│  4. GENERATE credentials                                     │
│     vault read database/postgresql/creds/readonly            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Section 4: Statement Issues

### Symptoms
- `error creating user`
- `syntax error at or near`
- `SQL syntax error`
- `error executing creation statements`

### Diagnosis Steps

```bash
# 1. Read the role's creation statements
vault read database/<mount>/roles/<role>
# Look at creation_statements field

# 2. Test the statement manually (substitute placeholders)
# Replace {{name}} with a test username
# Replace {{password}} with a test password
# Replace {{expiration}} with a timestamp

# 3. Execute the statement directly in database client
# to see the actual error message
```

### Common Causes & Fixes

| Cause | Fix |
|-------|-----|
| Syntax error in SQL | Test SQL directly in database client first |
| Missing quotes around placeholders | Use proper quoting for your DB type |
| Placeholder format wrong | Must be `{{name}}`, `{{password}}`, `{{expiration}}` |
| Statement incompatible with DB version | Check DB version-specific syntax |
| Missing semicolons | Add semicolons between statements |

### Placeholder Reference

```
┌─────────────────────────────────────────────────────────────┐
│                 AVAILABLE PLACEHOLDERS                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  {{name}}       - Generated username (e.g., v-token-ro-abc) │
│  {{password}}   - Generated random password                  │
│  {{expiration}} - Timestamp when credential expires          │
│                   (format varies by database)                │
│                                                              │
│  IMPORTANT: The exact format and quoting depends on your     │
│  database type. Check official Vault docs for examples.      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Section 5: Lease Issues

### Symptoms
- `lease not found`
- `lease already expired`
- `cannot renew`
- `max TTL exceeded`

### Diagnosis Steps

```bash
# 1. Look up specific lease
vault lease lookup <lease_id>

# 2. List active leases for a path
vault list sys/leases/lookup/database/<mount>/creds/<role>

# 3. Check Vault audit logs for lease operations
# (if audit logging is enabled)

# 4. Check default and max TTL for the role
vault read database/<mount>/roles/<role>
```

### Common Causes & Fixes

| Cause | Fix |
|-------|-----|
| Lease expired | Generate new credentials |
| Trying to renew past max_ttl | Cannot extend beyond max_ttl |
| Lease was explicitly revoked | Generate new credentials |
| Vault restarted without persistent storage | Leases lost; reconfigure |

### TTL Behavior

```
Time ────────────────────────────────────────────────────────────────▶

Request    default_ttl         max_ttl
│          │                   │
▼          ▼                   ▼
├──────────┼───────────────────┤
│  VALID   │  RENEWABLE        │  CANNOT RENEW PAST THIS
│          │                   │
└──────────┴───────────────────┘

Key points:
- Initial TTL = default_ttl (from role config)
- Can renew to extend TTL
- CANNOT renew past max_ttl (hard limit)
- After max_ttl: credential is revoked
```

---

## Section 6: Revocation Issues

### Symptoms
- `error revoking lease`
- `revocation failed`
- User still exists after revocation
- `role does not exist` during revocation

### Diagnosis Steps

```bash
# 1. Check revocation statements in role
vault read database/<mount>/roles/<role>
# Look at revocation_statements field

# 2. Manually test revocation statement
# Replace {{name}} with the actual generated username

# 3. Verify admin user has DROP privileges

# 4. Check if user owns objects (PostgreSQL specific)
# Some DBs prevent dropping users that own objects
```

### Common Causes & Fixes

| Cause | Fix |
|-------|-----|
| Revocation statement has syntax error | Fix and update role |
| Admin lacks DROP privilege | Grant DROP/DELETE privileges |
| User owns database objects | Revocation statement must handle this |
| User has active connections | May need to terminate connections first |
| Role was deleted while leases exist | Orphaned leases; manual cleanup |

---

## General Diagnostic Commands

```bash
# ═══════════════════════════════════════════════════════════
# VAULT HEALTH & STATUS
# ═══════════════════════════════════════════════════════════

# Check Vault status
vault status

# Check secrets engines mounted
vault secrets list

# ═══════════════════════════════════════════════════════════
# DATABASE SECRETS ENGINE STATE
# ═══════════════════════════════════════════════════════════

# List all database connections
vault list database/config

# Read connection details
vault read database/<mount>/config/<name>

# List all roles
vault list database/<mount>/roles

# Read role details
vault read database/<mount>/roles/<role>

# ═══════════════════════════════════════════════════════════
# LEASE MANAGEMENT
# ═══════════════════════════════════════════════════════════

# Generate credentials (and note the lease_id)
vault read database/<mount>/creds/<role>

# Look up lease details
vault lease lookup <lease_id>

# Renew a lease
vault lease renew <lease_id>

# Revoke a specific lease
vault lease revoke <lease_id>

# Revoke all leases for a role (prefix revocation)
vault lease revoke -prefix database/<mount>/creds/<role>

# ═══════════════════════════════════════════════════════════
# NETWORK TESTING (from Vault node)
# ═══════════════════════════════════════════════════════════

# Test port connectivity
nc -zv <DB_HOST> <DB_PORT>
telnet <DB_HOST> <DB_PORT>

# DNS resolution
nslookup <DB_HOST>
dig <DB_HOST>
```

---

## Error Message Reference

| Error Message | Likely Cause | Section |
|---------------|--------------|---------|
| `connection refused` | Database not reachable | 1 |
| `i/o timeout` | Network/firewall blocking | 1 |
| `authentication failed` | Wrong credentials | 2 |
| `Access denied` | Insufficient privileges | 2 |
| `role not found` | Role doesn't exist | 3 |
| `no database found` | Connection not configured | 3 |
| `syntax error` | Bad creation/revocation statement | 4 |
| `lease not found` | Expired or revoked lease | 5 |
| `max TTL exceeded` | Cannot renew past limit | 5 |
| `failed to find entry for connection` | Orphaned lease during destroy | 7 |

---

## Section 7: Terraform Destroy Issues

### Symptoms
- `terraform destroy` fails with error:
  ```
  Error: error deleting from Vault: failed to revoke "database/<mount>/creds/<role>/<lease_id>"
  failed to find entry for connection with name: "<connection>"
  ```

### Why This Happens

Terraform's dependency graph sometimes destroys the database connection config before all leases are revoked. Vault then cannot revoke the orphaned leases because the connection they reference no longer exists.

```
┌─────────────────────────────────────────────────────────────┐
│                    WHAT GOES WRONG                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. You generate credentials → creates lease                 │
│  2. terraform destroy runs                                   │
│  3. Connection config gets deleted                           │
│  4. Vault tries to revoke lease → needs connection config    │
│  5. Connection is gone → revocation fails                    │
│  6. terraform destroy fails                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Fix: Force Revoke Before Destroy

```bash
# Revoke all leases under this mount
vault lease revoke -force -prefix database/<mount>/

# If that fails, disable the entire mount
vault secrets disable database/<mount>

# Now terraform destroy will work
terraform destroy
```

### Prevention: Revoke Leases Before Destroy

Before running `terraform destroy`, always revoke active leases:

```bash
# Get the cleanup command from terraform output
terraform output pre_destroy_cleanup

# Run the cleanup command
vault lease revoke -prefix database/<mount>/

# Now safe to destroy
terraform destroy
```

---

## Related Documentation

- [Database Secrets Flow](database-secrets-flow.md) - How credential lifecycle works
- [Official Vault Database Secrets Docs](https://developer.hashicorp.com/vault/docs/secrets/databases)
