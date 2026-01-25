# Vault OpenLDAP Troubleshooting Guide

A visual, phase-based approach to troubleshooting Vault LDAP authentication with OpenLDAP.

> **Need to understand the flow?** See [auth-flow.md](auth-flow.md) for how the authentication process works.

---

## Authentication Flow Mental Map

Understanding WHERE in the flow your error occurs is the key to fast resolution.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    VAULT LDAP AUTHENTICATION PHASES                             │
└─────────────────────────────────────────────────────────────────────────────────┘

  USER                        VAULT                         OPENLDAP SERVER
    │                           │                                  │
    │  vault login -method=ldap │                                  │
    │  username=<user>          │                                  │
    │ ─────────────────────────>│                                  │
    │                           │                                  │
    │                           │  ┌─────────────────────────────┐ │
    │                           │  │ PHASE 1: CONNECTIVITY       │ │
    │                           │  │ Can Vault reach OpenLDAP?   │ │
    │                           │  └─────────────────────────────┘ │
    │                           │                                  │
    │                           │  TCP connect to port 389/636 ───>│
    │                           │                                  │
    │                           │  ┌─────────────────────────────┐ │
    │                           │  │ PHASE 2: SERVICE BIND       │ │
    │                           │  │ Can Vault authenticate to   │ │
    │                           │  │ OpenLDAP as service account?│ │
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
    │                           │  │ Map LDAP groups to policies │ │
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
           Check: Firewall, security groups, slapd running, correct IP/port

  "Invalid Credentials" (Code 49) on login attempt
      │
      ├── Does ldapsearch with service account work?
      │       │
      │       NO ──> PHASE 2: Service Account Bind
      │              Check: binddn format (full DN), bindpass, account exists
      │       │
      │       YES ─> PHASE 4: User Authentication
      │              Check: User password, user account exists

  "User not found" / "No such object" (Code 32)
      └──> PHASE 3: User Discovery
           Check: userdn path, userattr (uid), user exists in that OU

  Login succeeds but wrong policies / only "default" policy
      │
      ├── Are groups returned by ldapsearch?
      │       │
      │       NO ──> PHASE 5: Group Resolution
      │              Check: groupdn, groupfilter, member attribute format
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
│  VAULT SERVER                           OPENLDAP SERVER          │
│       │                                        │                 │
│       │──── TCP SYN to port 389 ──────────────>│                 │
│       │                                        │                 │
│       │     Firewall? Security Group?          │                 │
│       │     Wrong IP? slapd not running?       │                 │
│       │                                        │                 │
│       │<─── Connection refused / timeout ──────│                 │
└──────────────────────────────────────────────────────────────────┘
```

### Diagnostic Commands

```bash
# Test TCP connectivity (run from Vault server or same network)
nc -zv <LDAP_SERVER> 389
nc -zv <LDAP_SERVER> 636    # For LDAPS

# Alternative
telnet <LDAP_SERVER> 389

# Test if LDAP responds (anonymous query - may or may not work)
ldapsearch -x -H ldap://<LDAP_SERVER>:389 -b "" -s base "(objectClass=*)"
```

### Common Causes

| Cause | Solution |
|-------|----------|
| Firewall/Security Group blocking | Open ports 389 (LDAP), 636 (LDAPS) from Vault to OpenLDAP |
| Wrong IP address | Verify server IP; use private IP if same VPC |
| slapd not running | On LDAP server: `systemctl status slapd` |
| DNS resolution failure | Use IP address directly, or fix DNS |
| Using public IP when should use private | In cloud VPCs, use private IPs for internal traffic |

### OpenLDAP Server Check

```bash
# On the OpenLDAP server
systemctl status slapd
journalctl -u slapd -f
```

---

## Phase 2: Service Account Bind

**Symptom:** `Invalid Credentials` (Code 49) when Vault tries to connect

```
┌──────────────────────────────────────────────────────────────────┐
│  VAULT                                   OPENLDAP SERVER         │
│    │                                           │                 │
│    │  BIND DN: cn=admin,dc=domain,dc=com       │                 │
│    │  Password: ********                       │                 │
│    │ ─────────────────────────────────────────>│                 │
│    │                                           │                 │
│    │            Wrong DN? Wrong password?      │                 │
│    │            DN doesn't exist?              │                 │
│    │                                           │                 │
│    │<──────────── Code 49: Invalid Credentials │                 │
└──────────────────────────────────────────────────────────────────┘
```

### Diagnostic Commands

```bash
# Test service account bind with full DN
ldapsearch -x -H ldap://<LDAP_SERVER>:389 \
    -D "cn=admin,dc=<DOMAIN>,dc=<TLD>" \
    -w "<ADMIN_PASSWORD>" \
    -b "dc=<DOMAIN>,dc=<TLD>" \
    "(objectClass=*)" dn
```

### Common Causes

| Cause | Solution |
|-------|----------|
| Wrong binddn format | OpenLDAP requires FULL DN: `cn=admin,dc=example,dc=com` |
| Typo in password | Verify password; special characters may need escaping |
| Admin entry doesn't exist | Verify with ldapsearch that the DN exists |
| Wrong Base DN | Verify `dc=` components match your domain |

### Key Difference: OpenLDAP vs AD

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CRITICAL: binddn format                                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  OpenLDAP:  binddn = "cn=admin,dc=example,dc=com"    (Full DN required)     │
│  AD:        binddn = "admin@example.com"              (UPN works)            │
│                                                                             │
│  OpenLDAP does NOT support UPN-style binds like Active Directory!           │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Vault Config Check

```bash
vault read auth/ldap/config | grep -E "binddn|url"
```

---

## Phase 3: User Discovery

**Symptom:** `user not found`, `No such object` (Code 32)

```
┌──────────────────────────────────────────────────────────────────┐
│  VAULT (bound as service account)            OPENLDAP SERVER     │
│    │                                               │             │
│    │  SEARCH base: ou=users,dc=domain,dc=com       │             │
│    │  Filter: (uid=alice)                          │             │
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
ldapsearch -x -H ldap://<LDAP_SERVER>:389 \
    -D "cn=admin,dc=<DOMAIN>,dc=<TLD>" \
    -w "<ADMIN_PASSWORD>" \
    -b "ou=users,dc=<DOMAIN>,dc=<TLD>" \
    "(uid=<USERNAME>)" dn uid

# List all users to verify they exist
ldapsearch -x -H ldap://<LDAP_SERVER>:389 \
    -D "cn=admin,dc=<DOMAIN>,dc=<TLD>" \
    -w "<ADMIN_PASSWORD>" \
    -b "ou=users,dc=<DOMAIN>,dc=<TLD>" \
    "(objectClass=inetOrgPerson)" uid

# Search entire directory (if user might be in different OU)
ldapsearch -x -H ldap://<LDAP_SERVER>:389 \
    -D "cn=admin,dc=<DOMAIN>,dc=<TLD>" \
    -w "<ADMIN_PASSWORD>" \
    -b "dc=<DOMAIN>,dc=<TLD>" \
    "(uid=<USERNAME>)" dn
```

### Common Causes

| Cause | Solution |
|-------|----------|
| Wrong `userattr` | OpenLDAP uses `uid`, NOT `sAMAccountName` (that's AD!) |
| Wrong `userdn` | Check container: `ou=users` vs `ou=people` vs other OU |
| User in different OU | Broaden search or update `userdn` to correct OU |
| User doesn't exist | Verify user was created in LDAP |
| Typo in username | Check exact `uid` spelling |

### Key Difference: OpenLDAP vs AD

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CRITICAL: userattr setting                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  OpenLDAP:        userattr = "uid"                                          │
│  Active Directory: userattr = "sAMAccountName"                               │
│                                                                             │
│  This is the #1 cause of "user not found" when copying configs from AD!     │
└─────────────────────────────────────────────────────────────────────────────┘
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
│  VAULT                                       OPENLDAP SERVER     │
│    │                                               │             │
│    │  BIND as: uid=alice,ou=users,dc=domain,dc=com │             │
│    │  Password: (user's password)                  │             │
│    │ ─────────────────────────────────────────────>│             │
│    │                                               │             │
│    │        Wrong password?                        │             │
│    │        User entry has no userPassword?        │             │
│    │                                               │             │
│    │<────────────────────── Code 49                │             │
└──────────────────────────────────────────────────────────────────┘
```

### Diagnostic Commands

```bash
# Test user bind directly
ldapsearch -x -H ldap://<LDAP_SERVER>:389 \
    -D "uid=<USERNAME>,ou=users,dc=<DOMAIN>,dc=<TLD>" \
    -w "<USER_PASSWORD>" \
    -b "dc=<DOMAIN>,dc=<TLD>" \
    "(uid=<USERNAME>)"

# Check if user has a password set
ldapsearch -x -H ldap://<LDAP_SERVER>:389 \
    -D "cn=admin,dc=<DOMAIN>,dc=<TLD>" \
    -w "<ADMIN_PASSWORD>" \
    -b "ou=users,dc=<DOMAIN>,dc=<TLD>" \
    "(uid=<USERNAME>)" userPassword
```

### Common Causes

| Cause | Solution |
|-------|----------|
| Wrong password | Verify user password |
| No password set | User entry missing `userPassword` attribute |
| Password hash issue | Ensure password was set correctly with `ldappasswd` or LDIF |

---

## Phase 5: Group Resolution

**Symptom:** Login succeeds but token has no policies (only "default")

```
┌──────────────────────────────────────────────────────────────────┐
│  VAULT                                       OPENLDAP SERVER     │
│    │                                               │             │
│    │  SEARCH base: ou=groups,dc=domain,dc=com      │             │
│    │  Filter: (member=uid=alice,ou=users,dc=...)   │             │
│    │ ─────────────────────────────────────────────>│             │
│    │                                               │             │
│    │     Wrong groupdn? Wrong filter?              │             │
│    │     Member attribute format wrong?            │             │
│    │                                               │             │
│    │<────────────────────── 0 groups returned      │             │
└──────────────────────────────────────────────────────────────────┘
```

### Diagnostic Commands

```bash
# List all groups
ldapsearch -x -H ldap://<LDAP_SERVER>:389 \
    -D "cn=admin,dc=<DOMAIN>,dc=<TLD>" \
    -w "<ADMIN_PASSWORD>" \
    -b "ou=groups,dc=<DOMAIN>,dc=<TLD>" \
    "(objectClass=groupOfNames)" cn member

# Test the groupfilter directly (replace with actual user DN)
ldapsearch -x -H ldap://<LDAP_SERVER>:389 \
    -D "cn=admin,dc=<DOMAIN>,dc=<TLD>" \
    -w "<ADMIN_PASSWORD>" \
    -b "ou=groups,dc=<DOMAIN>,dc=<TLD>" \
    "(member=uid=<USERNAME>,ou=users,dc=<DOMAIN>,dc=<TLD>)" cn

# Check what the exact member values look like
ldapsearch -x -H ldap://<LDAP_SERVER>:389 \
    -D "cn=admin,dc=<DOMAIN>,dc=<TLD>" \
    -w "<ADMIN_PASSWORD>" \
    -b "ou=groups,dc=<DOMAIN>,dc=<TLD>" \
    "(cn=<GROUP_NAME>)" member
```

### Common Causes

| Cause | Solution |
|-------|----------|
| Wrong `groupdn` | Ensure it points to container with groups |
| Wrong `groupfilter` | OpenLDAP typically: `(member={{.UserDN}})` |
| User not in any groups | Add user to appropriate LDAP groups |
| Member DN format mismatch | Verify member values match user DN exactly |
| Groups use different objectClass | May be `groupOfNames` or `posixGroup` |

### The groupfilter Template

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  GROUPFILTER EXPLAINED                                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  groupfilter = "(member={{.UserDN}})"                                       │
│                         ▲                                                   │
│                         │                                                   │
│                         └── Vault replaces this with the user's full DN     │
│                                                                             │
│  For user "alice", Vault searches:                                          │
│                                                                             │
│  (member=uid=alice,ou=users,dc=example,dc=com)                              │
│                                                                             │
│  The group entry must have EXACTLY this value in its member attribute!      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

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
│  LDAP Returns:          Vault Group Config:        Vault Policies:          │
│                                                                             │
│  ┌─────────────┐       ┌─────────────────────┐    ┌─────────────────┐      │
│  │ vault-admins│ ─────>│ auth/ldap/groups/   │───>│ ldap-admins     │      │
│  └─────────────┘       │ vault-admins        │    └─────────────────┘      │
│                        └─────────────────────┘                              │
│                                  ▲                                          │
│                                  │                                          │
│                        CASE-SENSITIVE MATCH!                                │
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
| Group name case mismatch | Vault group name must EXACTLY match LDAP group CN |
| Group mapping doesn't exist | Create with `vault write auth/ldap/groups/<NAME>` |
| Policy doesn't exist | Create the policy first |
| Typo in policy name | Verify policy name spelling |

### Creating Correct Group Mappings

```bash
# First, find exact group name from LDAP
ldapsearch -x -H ldap://<LDAP_SERVER>:389 \
    -D "cn=admin,dc=<DOMAIN>,dc=<TLD>" \
    -w "<ADMIN_PASSWORD>" \
    -b "ou=groups,dc=<DOMAIN>,dc=<TLD>" \
    "(objectClass=groupOfNames)" cn

# Output: cn: vault-admins   <-- Use this EXACT case

# Create mapping with EXACT case
vault write auth/ldap/groups/vault-admins policies="ldap-admins"

# WRONG - case doesn't match:
vault write auth/ldap/groups/Vault-Admins policies="ldap-admins"  # Won't work!
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
    -H ldap://<LDAP_SERVER>:<PORT> \
    -D "<BIND_DN>" \
    -w "<BIND_PASSWORD>" \
    -b "<SEARCH_BASE>" \
    "<FILTER>" \
    <ATTRIBUTES>

# Example with common OpenLDAP values:
ldapsearch -x \
    -H ldap://10.0.1.50:389 \
    -D "cn=admin,dc=example,dc=com" \
    -w "adminpassword" \
    -b "ou=users,dc=example,dc=com" \
    "(uid=alice)" \
    dn uid cn mail
```

### Verify Full Configuration

```bash
# Dump full LDAP auth config
vault read auth/ldap/config

# Expected OpenLDAP configuration:
#   url            = ldap://<LDAP_SERVER>:389
#   binddn         = cn=admin,dc=<DOMAIN>,dc=<TLD>
#   userdn         = ou=users,dc=<DOMAIN>,dc=<TLD>
#   userattr       = uid                        <-- NOT sAMAccountName!
#   groupdn        = ou=groups,dc=<DOMAIN>,dc=<TLD>
#   groupattr      = cn
#   groupfilter    = (member={{.UserDN}})
```

---

## OpenLDAP Server Diagnostics

### Check Service Status

```bash
# On the OpenLDAP server
systemctl status slapd
journalctl -u slapd -f
```

### Verify Database Contents

```bash
# List all entries
ldapsearch -x -H ldap://localhost:389 \
    -D "cn=admin,dc=<DOMAIN>,dc=<TLD>" \
    -w "<ADMIN_PASSWORD>" \
    -b "dc=<DOMAIN>,dc=<TLD>" \
    "(objectClass=*)" dn

# Check if required schemas are loaded
ldapsearch -x -H ldap://localhost:389 \
    -b "cn=schema,cn=config" \
    "(objectClass=*)" | grep -i inetorgperson
```

---

## Configuration Validation Checklist

```
[ ] OpenLDAP server is reachable from Vault (port 389/636 open)
[ ] binddn exists and uses full DN format (cn=admin,dc=..., NOT UPN)
[ ] binddn has read permissions on userdn and groupdn
[ ] Users exist under userdn with uid attribute
[ ] userattr is set to "uid" (not sAMAccountName)
[ ] Groups exist under groupdn with member attribute
[ ] groupfilter uses (member={{.UserDN}}) format
[ ] member attribute contains full user DNs
[ ] Vault group mappings match LDAP group CNs (case-sensitive)
[ ] Policies exist and are attached to Vault groups
```

---

## Quick Reset Procedure

If LDAP auth is misconfigured and you need to start fresh:

```bash
# Disable and re-enable LDAP auth (clears all config)
vault auth disable ldap
vault auth enable ldap

# Reconfigure from scratch
vault write auth/ldap/config \
    url="ldap://<LDAP_SERVER>:389" \
    binddn="cn=admin,dc=<DOMAIN>,dc=<TLD>" \
    bindpass="<ADMIN_PASSWORD>" \
    userdn="ou=users,dc=<DOMAIN>,dc=<TLD>" \
    userattr="uid" \
    groupdn="ou=groups,dc=<DOMAIN>,dc=<TLD>" \
    groupattr="cn" \
    groupfilter="(member={{.UserDN}})"

# Recreate group mappings (use EXACT case from LDAP)
vault write auth/ldap/groups/<GROUP_NAME> policies="<POLICY_NAME>"
```

---

## Quick Reference: OpenLDAP vs AD

| Parameter | OpenLDAP | Active Directory |
|-----------|----------|------------------|
| `userattr` | `uid` | `sAMAccountName` |
| `userdn` | `ou=users,dc=...` | `CN=Users,DC=...` |
| `binddn` format | Full DN required | UPN (`user@domain`) works |
| `groupfilter` | `(member={{.UserDN}})` | Includes OID for nesting |
| Nested groups | NOT supported | Supported via OID |
| Group names in Vault | Case-sensitive match | Case-sensitive match |
