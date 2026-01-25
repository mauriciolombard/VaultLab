# Vault LDAP/Active Directory Troubleshooting Guide

A visual, phase-based approach to troubleshooting Vault LDAP authentication with Active Directory.

---

## Authentication Flow Mental Map

Understanding WHERE in the flow your error occurs is the key to fast resolution.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    VAULT LDAP AUTHENTICATION PHASES                             │
└─────────────────────────────────────────────────────────────────────────────────┘

  USER                        VAULT                         ACTIVE DIRECTORY
    │                           │                                  │
    │  vault login -method=ldap │                                  │
    │  username=<user>          │                                  │
    │ ─────────────────────────>│                                  │
    │                           │                                  │
    │                           │  ┌─────────────────────────────┐ │
    │                           │  │ PHASE 1: CONNECTIVITY       │ │
    │                           │  │ Can Vault reach AD?         │ │
    │                           │  └─────────────────────────────┘ │
    │                           │                                  │
    │                           │  TCP connect to port 389/636 ───>│
    │                           │                                  │
    │                           │  ┌─────────────────────────────┐ │
    │                           │  │ PHASE 2: SERVICE BIND       │ │
    │                           │  │ Can Vault authenticate to   │ │
    │                           │  │ AD as service account?      │ │
    │                           │  └─────────────────────────────┘ │
    │                           │                                  │
    │                           │  BIND binddn + bindpass ────────>│
    │                           │<──────────────────── Success/Fail│
    │                           │                                  │
    │                           │  ┌─────────────────────────────┐ │
    │                           │  │ PHASE 3: USER DISCOVERY     │ │
    │                           │  │ Can Vault find the user     │ │
    │                           │  │ in the directory?           │ │
    │                           │  └─────────────────────────────┘ │
    │                           │                                  │
    │                           │  SEARCH userdn for userattr ────>│
    │                           │<─────────────────────── User DN  │
    │                           │                                  │
    │                           │  ┌─────────────────────────────┐ │
    │                           │  │ PHASE 4: USER AUTH          │ │
    │                           │  │ Is the user's password      │ │
    │                           │  │ correct?                    │ │
    │                           │  └─────────────────────────────┘ │
    │                           │                                  │
    │                           │  BIND as user DN + password ────>│
    │                           │<──────────────────── Success/Fail│
    │                           │                                  │
    │                           │  ┌─────────────────────────────┐ │
    │                           │  │ PHASE 5: GROUP RESOLUTION   │ │
    │                           │  │ What groups is the user     │ │
    │                           │  │ a member of?                │ │
    │                           │  └─────────────────────────────┘ │
    │                           │                                  │
    │                           │  SEARCH groupdn with filter ────>│
    │                           │<────────────────────── Group CNs │
    │                           │                                  │
    │                           │  ┌─────────────────────────────┐ │
    │                           │  │ PHASE 6: POLICY MAPPING     │ │
    │                           │  │ (Vault-side only)           │ │
    │                           │  │ Map AD groups to policies   │ │
    │                           │  └─────────────────────────────┘ │
    │                           │                                  │
    │<────── Token + Policies ──│                                  │
    │                           │                                  │
```

---

## Quick Diagnostic: Which Phase Is Failing?

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                         ERROR DECISION TREE                                     │
└────────────────────────────────────────────────────────────────────────────────┘

  "Connection refused" / "Network Error" (Code 200)
      └──> PHASE 1: Connectivity
           Check: Firewall, security groups, AD server running, correct IP/port

  "Invalid Credentials" (Code 49) on login attempt
      │
      ├── Does ldapsearch with service account work?
      │       │
      │       NO ──> PHASE 2: Service Account Bind
      │              Check: binddn format, bindpass, account locked/disabled
      │       │
      │       YES ─> PHASE 4: User Authentication
      │              Check: User password, account locked/expired
      │
  "User not found" / "No such object" (Code 32)
      └──> PHASE 3: User Discovery
           Check: userdn path, userattr (sAMAccountName vs uid), user exists

  Login succeeds but wrong policies / only "default" policy
      │
      ├── Are groups returned by ldapsearch?
      │       │
      │       NO ──> PHASE 5: Group Resolution
      │              Check: groupdn, groupfilter, nested group OID
      │       │
      │       YES ─> PHASE 6: Policy Mapping
      │              Check: Vault group names (CASE-SENSITIVE!), policy exists
```

---

## LDAP Result Codes Reference

| Code | Name | Meaning | Likely Phase |
|------|------|---------|--------------|
| 0 | Success | Operation completed | - |
| 1 | Operations Error | Server-side error | Any |
| 32 | No Such Object | DN path doesn't exist | 3 (User Discovery) |
| 34 | Invalid DN Syntax | Malformed DN | 2, 3 |
| 49 | Invalid Credentials | Wrong password or bind DN | 2, 4 |
| 50 | Insufficient Access | Permission denied | 2, 3, 5 |
| 52 | Unavailable | Server not accepting connections | 1 |
| 81 | Server Down | Cannot contact server | 1 |
| 200 | Network Error | Connection failed | 1 |

---

## Phase 1: Connectivity

**Symptom:** `connection refused`, `network error`, `server down`, timeout

```
┌──────────────────────────────────────────────────────────────────┐
│  VAULT SERVER                              AD SERVER             │
│       │                                        │                 │
│       │──── TCP SYN to port 389 ──────────────>│                 │
│       │                                        │                 │
│       │     Firewall? Security Group?          │                 │
│       │     Wrong IP? AD not running?          │                 │
│       │                                        │                 │
│       │<─── Connection refused / timeout ──────│                 │
└──────────────────────────────────────────────────────────────────┘
```

### Diagnostic Commands

```bash
# Test TCP connectivity (run from Vault server or same network)
nc -zv <AD_SERVER> 389
nc -zv <AD_SERVER> 636    # For LDAPS

# Alternative
telnet <AD_SERVER> 389

# Test if LDAP responds (anonymous RootDSE query - usually allowed)
ldapsearch -x -H ldap://<AD_SERVER>:389 -b "" -s base "(objectClass=*)"
```

### Common Causes

| Cause | Solution |
|-------|----------|
| Firewall/Security Group blocking | Open ports 389 (LDAP), 636 (LDAPS) from Vault to AD |
| Wrong IP address | Verify AD server IP; use private IP if same VPC |
| AD server not running | Check AD DS service status on Windows server |
| DNS resolution failure | Use IP address directly, or fix DNS |
| Using public IP when should use private | In cloud VPCs, use private IPs for internal traffic |

---

## Phase 2: Service Account Bind

**Symptom:** `Invalid Credentials` (Code 49) when Vault tries to connect

```
┌──────────────────────────────────────────────────────────────────┐
│  VAULT                                     AD SERVER             │
│    │                                           │                 │
│    │  BIND DN: vault-svc@domain.com            │                 │
│    │  Password: ********                       │                 │
│    │ ─────────────────────────────────────────>│                 │
│    │                                           │                 │
│    │            Wrong format? Wrong password?  │                 │
│    │            Account locked? Account disabled?                │
│    │                                           │                 │
│    │<──────────── Code 49: Invalid Credentials │                 │
└──────────────────────────────────────────────────────────────────┘
```

### Diagnostic Commands

```bash
# Test service account bind - try different formats:

# UPN format (recommended for AD)
ldapsearch -x -H ldap://<AD_SERVER>:389 \
    -D "<SERVICE_ACCOUNT>@<DOMAIN>" \
    -w "<PASSWORD>" \
    -b "" -s base

# DN format
ldapsearch -x -H ldap://<AD_SERVER>:389 \
    -D "CN=<SERVICE_ACCOUNT>,CN=Users,DC=<DOMAIN>,DC=<TLD>" \
    -w "<PASSWORD>" \
    -b "" -s base

# DOMAIN\user format (less common)
ldapsearch -x -H ldap://<AD_SERVER>:389 \
    -D "<NETBIOS>\\<SERVICE_ACCOUNT>" \
    -w "<PASSWORD>" \
    -b "" -s base
```

### Common Causes

| Cause | Solution |
|-------|----------|
| Wrong binddn format | AD prefers UPN: `user@domain.com` |
| Typo in password | Verify password; special characters may need escaping |
| Account locked out | Check AD for lockout; too many failed attempts |
| Account disabled | Enable account in AD Users and Computers |
| Account expired | Check account expiration in AD |
| Password expired | Reset password or set "Password never expires" for service accounts |

### Vault Config Check

```bash
vault read auth/ldap/config | grep -E "binddn|url"
```

---

## Phase 3: User Discovery

**Symptom:** `user not found`, `No such object` (Code 32)

```
┌──────────────────────────────────────────────────────────────────┐
│  VAULT (bound as service account)              AD SERVER         │
│    │                                               │             │
│    │  SEARCH base: CN=Users,DC=domain,DC=com       │             │
│    │  Filter: (sAMAccountName=alice)               │             │
│    │ ─────────────────────────────────────────────>│             │
│    │                                               │             │
│    │     Wrong base DN? Wrong attribute?           │             │
│    │     User in different OU? User doesn't exist? │             │
│    │                                               │             │
│    │<────────────────────── 0 results / Code 32    │             │
└──────────────────────────────────────────────────────────────────┘
```

### Diagnostic Commands

```bash
# Search for a specific user
ldapsearch -x -H ldap://<AD_SERVER>:389 \
    -D "<SERVICE_ACCOUNT>@<DOMAIN>" \
    -w "<PASSWORD>" \
    -b "CN=Users,DC=<DOMAIN>,DC=<TLD>" \
    "(sAMAccountName=<USERNAME>)" dn sAMAccountName

# List all users to verify they exist
ldapsearch -x -H ldap://<AD_SERVER>:389 \
    -D "<SERVICE_ACCOUNT>@<DOMAIN>" \
    -w "<PASSWORD>" \
    -b "CN=Users,DC=<DOMAIN>,DC=<TLD>" \
    "(objectClass=user)" sAMAccountName

# Search entire domain (if user might be in different OU)
ldapsearch -x -H ldap://<AD_SERVER>:389 \
    -D "<SERVICE_ACCOUNT>@<DOMAIN>" \
    -w "<PASSWORD>" \
    -b "DC=<DOMAIN>,DC=<TLD>" \
    "(sAMAccountName=<USERNAME>)" dn
```

### Common Causes

| Cause | Solution |
|-------|----------|
| Wrong `userattr` | AD uses `sAMAccountName`, NOT `uid` (OpenLDAP uses `uid`) |
| Wrong `userdn` | Check container: `CN=Users` vs `OU=People` vs custom OU |
| User in different OU | Broaden search or update `userdn` to correct OU |
| User doesn't exist | Verify user exists in AD |
| Typo in username | Check exact `sAMAccountName` spelling |

### Key AD vs OpenLDAP Difference

```
┌─────────────────────────────────────────────────────────────┐
│  CRITICAL: userattr setting                                 │
├─────────────────────────────────────────────────────────────┤
│  Active Directory:  userattr = "sAMAccountName"             │
│  OpenLDAP:          userattr = "uid"                        │
│                                                             │
│  This is the #1 cause of "user not found" when migrating   │
│  configurations between AD and OpenLDAP!                    │
└─────────────────────────────────────────────────────────────┘
```

### Vault Config Check

```bash
vault read auth/ldap/config | grep -E "userdn|userattr"
```

---

## Phase 4: User Authentication

**Symptom:** `Invalid Credentials` (Code 49) - but service account works fine

```
┌──────────────────────────────────────────────────────────────────┐
│  VAULT                                         AD SERVER         │
│    │                                               │             │
│    │  BIND as: CN=Alice,CN=Users,DC=domain,DC=com  │             │
│    │  Password: (user's password)                  │             │
│    │ ─────────────────────────────────────────────>│             │
│    │                                               │             │
│    │        Wrong password? Account locked?        │             │
│    │        Account disabled? Password expired?    │             │
│    │                                               │             │
│    │<────────────────────── Code 49                │             │
└──────────────────────────────────────────────────────────────────┘
```

### Diagnostic Commands

```bash
# Test user bind directly
ldapsearch -x -H ldap://<AD_SERVER>:389 \
    -D "<USERNAME>@<DOMAIN>" \
    -w "<USER_PASSWORD>" \
    -b "" -s base
```

### Common Causes

| Cause | Solution |
|-------|----------|
| Wrong password | Verify user password |
| Account locked | Check lockout status in AD |
| Account disabled | Enable in AD Users and Computers |
| Password expired | User must change password |
| "Must change password at next logon" | Clear this flag or have user change password |

### AD Account Status Check (PowerShell on AD server)

```powershell
Get-ADUser -Identity "<USERNAME>" -Properties LockedOut, Enabled, PasswordExpired, PasswordLastSet
```

---

## Phase 5: Group Resolution

**Symptom:** Login succeeds but token has no policies (only "default")

```
┌──────────────────────────────────────────────────────────────────┐
│  VAULT                                         AD SERVER         │
│    │                                               │             │
│    │  SEARCH base: CN=Users,DC=domain,DC=com       │             │
│    │  Filter: (&(objectClass=group)                │             │
│    │           (member:1.2.840.113556.1.4.1941:=   │             │
│    │            CN=Alice,CN=Users,DC=...))         │             │
│    │ ─────────────────────────────────────────────>│             │
│    │                                               │             │
│    │     Wrong groupdn? Wrong filter?              │             │
│    │     Missing nested group OID?                 │             │
│    │                                               │             │
│    │<────────────────────── 0 groups returned      │             │
└──────────────────────────────────────────────────────────────────┘
```

### Diagnostic Commands

```bash
# Check user's memberOf attribute
ldapsearch -x -H ldap://<AD_SERVER>:389 \
    -D "<SERVICE_ACCOUNT>@<DOMAIN>" \
    -w "<PASSWORD>" \
    -b "CN=Users,DC=<DOMAIN>,DC=<TLD>" \
    "(sAMAccountName=<USERNAME>)" memberOf

# Test the groupfilter directly (replace USER_DN with actual DN)
ldapsearch -x -H ldap://<AD_SERVER>:389 \
    -D "<SERVICE_ACCOUNT>@<DOMAIN>" \
    -w "<PASSWORD>" \
    -b "CN=Users,DC=<DOMAIN>,DC=<TLD>" \
    "(&(objectClass=group)(member:1.2.840.113556.1.4.1941:=<USER_DN>))" cn

# List all groups
ldapsearch -x -H ldap://<AD_SERVER>:389 \
    -D "<SERVICE_ACCOUNT>@<DOMAIN>" \
    -w "<PASSWORD>" \
    -b "CN=Users,DC=<DOMAIN>,DC=<TLD>" \
    "(objectClass=group)" cn
```

### The Nested Group OID Explained

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  OID: 1.2.840.113556.1.4.1941 (LDAP_MATCHING_RULE_IN_CHAIN)                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Without OID:           With OID:                                           │
│                                                                             │
│  ┌─────────────┐        ┌─────────────┐                                     │
│  │ Domain-Admins│        │ Domain-Admins│                                    │
│  └──────┬──────┘        └──────┬──────┘                                     │
│         │                      │                                            │
│         │ member               │ member  ◄── OID searches recursively       │
│         ▼                      ▼                                            │
│  ┌─────────────┐        ┌─────────────┐                                     │
│  │ Vault-Admins│        │ Vault-Admins│                                     │
│  └──────┬──────┘        └──────┬──────┘                                     │
│         │                      │                                            │
│         │ member               │ member  ◄── OID finds Alice here too       │
│         ▼                      ▼                                            │
│  ┌─────────────┐        ┌─────────────┐                                     │
│  │    Alice    │        │    Alice    │                                     │
│  └─────────────┘        └─────────────┘                                     │
│                                                                             │
│  Query for Alice         Query for Alice                                    │
│  returns: Vault-Admins   returns: Vault-Admins AND Domain-Admins            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Common Causes

| Cause | Solution |
|-------|----------|
| Wrong `groupdn` | Ensure it points to container with groups |
| Missing nested group OID | Add `1.2.840.113556.1.4.1941` to groupfilter |
| User not in any groups | Add user to appropriate AD groups |
| Groups in different OU | Update `groupdn` or broaden search |
| `groupfilter` syntax error | Verify filter syntax, escape special chars |

### Vault Config Check

```bash
vault read auth/ldap/config | grep -E "groupdn|groupattr|groupfilter"
```

---

## Phase 6: Policy Mapping

**Symptom:** Groups are found but wrong policies attached to token

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        VAULT INTERNAL MAPPING                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  AD Returns:              Vault Group Config:        Vault Policies:        │
│                                                                             │
│  ┌─────────────┐         ┌─────────────────────┐    ┌─────────────────┐    │
│  │ Vault-Admins│ ───────>│ auth/ldap/groups/   │───>│ admin-policy    │    │
│  └─────────────┘         │ Vault-Admins        │    └─────────────────┘    │
│                          └─────────────────────┘                            │
│                                    ▲                                        │
│                                    │                                        │
│                          CASE-SENSITIVE MATCH!                              │
│                                                                             │
│  "vault-admins" ≠ "Vault-Admins" ≠ "VAULT-ADMINS"                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Diagnostic Commands

```bash
# List all Vault LDAP group mappings
vault list auth/ldap/groups

# Read specific group mapping
vault read auth/ldap/groups/<GROUP_NAME>

# Check what policies exist
vault policy list

# Check token after login
vault token lookup
```

### Common Causes

| Cause | Solution |
|-------|----------|
| Group name case mismatch | Vault group name must EXACTLY match AD group name |
| Group mapping doesn't exist | Create with `vault write auth/ldap/groups/<NAME>` |
| Policy doesn't exist | Create the policy first |
| Typo in policy name | Verify policy name spelling |

### Creating Correct Group Mappings

```bash
# First, find exact group name from AD
ldapsearch ... "(objectClass=group)" cn | grep -i vault

# Output: cn: Vault-Admins   <-- Use this EXACT case

# Create mapping with EXACT case
vault write auth/ldap/groups/Vault-Admins policies="admin-policy"

# WRONG - case doesn't match:
vault write auth/ldap/groups/vault-admins policies="admin-policy"  # Won't work!
```

---

## Debug Techniques

### Enable Vault Debug Logging

```bash
# In Vault config (config.hcl)
log_level = "debug"

# Or via environment variable
export VAULT_LOG_LEVEL=debug

# Watch logs for LDAP operations
journalctl -u vault -f | grep -i ldap

# Or if running in foreground
vault server -dev 2>&1 | grep -i ldap
```

### Generic ldapsearch Template

```bash
ldapsearch -x \
    -H ldap://<AD_SERVER>:<PORT> \
    -D "<BIND_DN>" \
    -w "<BIND_PASSWORD>" \
    -b "<SEARCH_BASE>" \
    "<FILTER>" \
    <ATTRIBUTES>
```

### Verify Full Configuration

```bash
# Dump full LDAP auth config
vault read auth/ldap/config

# Expected AD configuration:
#   url            = ldap://<AD_SERVER>:389
#   binddn         = <service_account>@<domain>
#   userdn         = CN=Users,DC=<domain>,DC=<tld>
#   userattr       = sAMAccountName           <-- NOT uid!
#   groupdn        = CN=Users,DC=<domain>,DC=<tld>
#   groupattr      = cn
#   groupfilter    = (&(objectClass=group)(member:1.2.840.113556.1.4.1941:={{.UserDN}}))
```

---

## Quick Reference: AD vs OpenLDAP

| Parameter | Active Directory | OpenLDAP |
|-----------|-----------------|----------|
| `userattr` | `sAMAccountName` | `uid` |
| `userdn` | `CN=Users,DC=...` | `ou=users,dc=...` |
| `binddn` format | `user@domain` (UPN) | Full DN |
| `groupfilter` | Includes OID `1.2.840.113556.1.4.1941` | Simple member filter |
| Nested groups | Supported via OID | Requires manual recursion |
| Group names in Vault | Case-sensitive match required | Case-sensitive match required |

---

## Reset Procedure

If LDAP auth is misconfigured beyond repair:

```bash
# Disable and re-enable (clears all config)
vault auth disable ldap
vault auth enable ldap

# Reconfigure from scratch
vault write auth/ldap/config \
    url="ldap://<AD_SERVER>:389" \
    binddn="<SERVICE_ACCOUNT>@<DOMAIN>" \
    bindpass="<PASSWORD>" \
    userdn="CN=Users,DC=<DOMAIN>,DC=<TLD>" \
    userattr="sAMAccountName" \
    groupdn="CN=Users,DC=<DOMAIN>,DC=<TLD>" \
    groupattr="cn" \
    groupfilter="(&(objectClass=group)(member:1.2.840.113556.1.4.1941:={{.UserDN}}))"

# Recreate group mappings (use EXACT case from AD)
vault write auth/ldap/groups/<EXACT_GROUP_NAME> policies="<POLICY_NAME>"
```
