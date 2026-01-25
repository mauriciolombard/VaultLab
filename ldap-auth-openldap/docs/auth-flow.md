# Understanding Vault + OpenLDAP Authentication

A conceptual guide to how Vault authenticates users against OpenLDAP.

> **Having issues?** See [troubleshooting.md](troubleshooting.md) for diagnosing and fixing problems.

---

## The Big Picture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           VAULT + OPENLDAP                                       │
└─────────────────────────────────────────────────────────────────────────────────┘

     ┌──────────┐              ┌──────────┐              ┌──────────────────┐
     │          │   credentials│          │  LDAP queries│                  │
     │   USER   │ ────────────>│  VAULT   │ ────────────>│    OPENLDAP      │
     │          │              │          │<────────────│                  │
     │          │<────────────│          │   user info  │   Directory      │
     └──────────┘    token     └──────────┘   & groups   │   Server         │
                                                         └──────────────────┘

  User provides:               Vault:                    OpenLDAP provides:
  • Username                   • Validates credentials   • User verification
  • Password                   • Queries group membership• Group membership
                               • Maps groups to policies • Directory structure
                               • Issues token
```

---

## OpenLDAP Concepts

### What is LDAP?

LDAP (Lightweight Directory Access Protocol) is a protocol for accessing directory services. Think of it like SQL for databases, but for directories that store hierarchical data like users and groups.

```
┌────────────────────────────────────────────────────────────────┐
│                    LDAP = THE PROTOCOL                          │
│                    OpenLDAP = THE SERVER                        │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│   Vault speaks LDAP  ───────────>  OpenLDAP understands LDAP   │
│                                                                │
│   "Find user alice"  ───────────>  "Here's alice's info"       │
│   "Is this password  ───────────>  "Yes" or "No"               │
│    correct?"                                                   │
│   "What groups is    ───────────>  "vault-admins, vault-users" │
│    alice in?"                                                  │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### What is OpenLDAP?

OpenLDAP is an open-source implementation of LDAP. It's commonly used on Linux systems and provides:
- **slapd** - The LDAP server daemon
- **ldapsearch/ldapadd/ldapmodify** - Command-line tools
- **Standard schemas** - For users (inetOrgPerson), groups (groupOfNames), etc.

---

## How Users Are Identified in OpenLDAP

OpenLDAP uses a hierarchical naming system. Understanding these concepts is crucial for Vault configuration.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     KEY OPENLDAP IDENTIFIERS                                     │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  DN (Distinguished Name) - The Full Path                                │   │
│  │  ═══════════════════════════════════════                                │   │
│  │                                                                         │   │
│  │  uid=alice,ou=users,dc=example,dc=com                                   │   │
│  │  ▲       ▲        ▲                                                     │   │
│  │  │       │        └── Domain components (read right to left)            │   │
│  │  │       └── Organizational Unit (container for users)                  │   │
│  │  └── User ID (unique identifier for this user)                          │   │
│  │                                                                         │   │
│  │  Like a file path: /com/example/users/alice                             │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  uid (User ID) - The Username                                           │   │
│  │  ════════════════════════════                                           │   │
│  │                                                                         │   │
│  │  alice                                                                  │   │
│  │                                                                         │   │
│  │  The simple username used for login                                     │   │
│  │  THIS IS WHAT VAULT SEARCHES FOR (userattr=uid)                         │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  Base DN - The Root of Your Directory                                   │   │
│  │  ════════════════════════════════════                                   │   │
│  │                                                                         │   │
│  │  dc=example,dc=com                                                      │   │
│  │                                                                         │   │
│  │  Derived from your domain: example.com → dc=example,dc=com              │   │
│  │  All entries in your directory live under this root                     │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Why This Matters for Vault

| Vault Config | Uses | Example |
|--------------|------|---------|
| `binddn` | Full DN of service account | `cn=admin,dc=example,dc=com` |
| `userattr` | Attribute to search for users | `uid` (searches for "alice") |
| `userdn` | Base DN where users are stored | `ou=users,dc=example,dc=com` |

---

## The OpenLDAP Directory Tree

Understanding where things live in OpenLDAP helps you configure Vault correctly.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    OPENLDAP DIRECTORY STRUCTURE                                  │
└─────────────────────────────────────────────────────────────────────────────────┘

dc=<DOMAIN>,dc=<TLD>                          ◄── Base DN (root of directory)
│
├── cn=admin                                  ◄── Admin account (binddn for Vault)
│   └── userPassword: {SSHA}...                   Used for searching users/groups
│
├── ou=users                                  ◄── User container (Vault's userdn)
│   │
│   ├── uid=alice                             ◄── A user entry
│   │   ├── objectClass: inetOrgPerson            (required for user attributes)
│   │   ├── cn: Alice Admin                       (display name)
│   │   ├── uid: alice                            (what Vault searches for)
│   │   ├── mail: alice@example.com
│   │   └── userPassword: {SSHA}...               (hashed password)
│   │
│   ├── uid=bob                               ◄── Another user
│   │   ├── uid: bob
│   │   └── ...
│   │
│   └── uid=charlie
│       └── ...
│
└── ou=groups                                 ◄── Group container (Vault's groupdn)
    │
    ├── cn=vault-admins                       ◄── A group entry
    │   ├── objectClass: groupOfNames
    │   ├── cn: vault-admins                      (what Vault returns as group name)
    │   └── member: uid=alice,ou=users,...        (full DN of each member)
    │
    └── cn=vault-users
        ├── cn: vault-users
        ├── member: uid=bob,ou=users,...
        └── member: uid=charlie,ou=users,...
```

### Key Insight: userdn Must Match User Location

```
┌────────────────────────────────────────────────────────────────────────────────┐
│  If users are in ou=users:                                                     │
│      userdn = "ou=users,dc=<DOMAIN>,dc=<TLD>"                                  │
│                                                                                │
│  If users are in ou=people:                                                    │
│      userdn = "ou=people,dc=<DOMAIN>,dc=<TLD>"                                 │
│                                                                                │
│  If users are scattered across multiple OUs:                                   │
│      userdn = "dc=<DOMAIN>,dc=<TLD>"  (search entire directory)                │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## The Authentication Journey

When a user runs `vault login -method=ldap username=alice`, here's what happens:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        THE AUTHENTICATION JOURNEY                                │
└─────────────────────────────────────────────────────────────────────────────────┘

  STEP 1: USER INITIATES LOGIN
  ════════════════════════════

       User                              Vault
        │                                  │
        │  "I am alice, my password is X"  │
        │ ────────────────────────────────>│
        │                                  │
        │     Vault now needs to verify    │
        │     this with OpenLDAP           │


  STEP 2: VAULT CONNECTS TO OPENLDAP (Service Account Bind)
  ═════════════════════════════════════════════════════════

       Vault                             OpenLDAP Server
        │                                      │
        │  BIND: cn=admin,dc=domain,dc=com     │
        │  PASSWORD: (service account pwd)     │
        │ ────────────────────────────────────>│
        │                                      │
        │     This is Vault's "admin"          │
        │     connection to OpenLDAP.          │
        │     It uses this to search.          │
        │                                      │
        │<──────────────────────────── OK ─────│


  STEP 3: VAULT SEARCHES FOR THE USER
  ════════════════════════════════════

       Vault                             OpenLDAP Server
        │                                      │
        │  SEARCH                              │
        │    Base: ou=users,dc=domain,...      │  ◄── userdn
        │    Filter: (uid=alice)               │  ◄── userattr
        │ ────────────────────────────────────>│
        │                                      │
        │<── DN: uid=alice,ou=users,dc=... ───│
        │                                      │
        │     Vault now knows the user's       │
        │     full Distinguished Name          │


  STEP 4: VAULT VERIFIES THE USER'S PASSWORD
  ═══════════════════════════════════════════

       Vault                             OpenLDAP Server
        │                                      │
        │  BIND: uid=alice,ou=users,dc=...     │  ◄── User's DN
        │  PASSWORD: (what user provided)      │
        │ ────────────────────────────────────>│
        │                                      │
        │     If this bind succeeds,           │
        │     the password is correct!         │
        │                                      │
        │<──────────────────────────── OK ─────│


  STEP 5: VAULT QUERIES GROUP MEMBERSHIP
  ═══════════════════════════════════════

       Vault                             OpenLDAP Server
        │                                      │
        │  SEARCH                              │
        │    Base: ou=groups,dc=domain,...     │  ◄── groupdn
        │    Filter: (member=uid=alice,...)    │  ◄── groupfilter
        │ ────────────────────────────────────>│
        │                                      │
        │<────────────── Groups: vault-admins ─│
        │                                      │
        │     OpenLDAP returns groups where    │
        │     alice's DN appears as a member   │


  STEP 6: VAULT MAPS GROUPS TO POLICIES
  ══════════════════════════════════════

       Vault (internal)
        │
        │  OpenLDAP returned: "vault-admins"
        │
        │  Vault checks: auth/ldap/groups/vault-admins
        │                    └── policies: ["ldap-admins"]
        │
        │  TOKEN ISSUED with policies:
        │    • ldap-admins
        │    • default
        │
       ─┴─
```

---

## Vault Configuration Explained

Each Vault LDAP config parameter maps to a specific part of the OpenLDAP integration.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    VAULT LDAP CONFIGURATION MAP                                  │
└─────────────────────────────────────────────────────────────────────────────────┘

vault write auth/ldap/config \
│
├── url="ldap://<LDAP_SERVER>:389"
│   │
│   └── WHERE ──────────────────────► Network location of OpenLDAP server
│                                      Port 389 = LDAP, Port 636 = LDAPS
│
├── binddn="cn=admin,dc=<DOMAIN>,dc=<TLD>"
│   │
│   └── WHO (service) ──────────────► Account Vault uses to search OpenLDAP
│                                      Needs read access to users/groups
│
├── bindpass="<PASSWORD>"
│   │
│   └── CREDENTIAL ─────────────────► Service account password
│
├── userdn="ou=users,dc=<DOMAIN>,dc=<TLD>"
│   │
│   └── WHERE TO FIND USERS ────────► Organizational Unit containing users
│                                      Must contain users who will log in
│
├── userattr="uid"
│   │
│   └── HOW TO FIND USERS ──────────► Attribute to match against username
│                                      OpenLDAP = uid, AD = sAMAccountName
│
├── groupdn="ou=groups,dc=<DOMAIN>,dc=<TLD>"
│   │
│   └── WHERE TO FIND GROUPS ───────► Organizational Unit containing groups
│
├── groupattr="cn"
│   │
│   └── GROUP NAME ATTRIBUTE ───────► What attribute contains the group name
│                                      Returns "vault-admins" not the full DN
│
└── groupfilter="(member={{.UserDN}})"
    │
    └── HOW TO FIND GROUPS ─────────► LDAP filter to find user's groups
                                       {{.UserDN}} = user's full Distinguished Name
```

---

## Group Membership in OpenLDAP

OpenLDAP typically uses the `member` attribute with full DNs.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    GROUP MEMBERSHIP MODEL                                        │
└─────────────────────────────────────────────────────────────────────────────────┘

  ┌───────────────────────────────────────────────────────────────────────────┐
  │  Group Entry: cn=vault-admins,ou=groups,dc=example,dc=com                 │
  ├───────────────────────────────────────────────────────────────────────────┤
  │                                                                           │
  │  objectClass: groupOfNames                                                │
  │  cn: vault-admins                                                         │
  │  member: uid=alice,ou=users,dc=example,dc=com    ◄── Full DN of alice    │
  │  member: uid=bob,ou=users,dc=example,dc=com      ◄── Full DN of bob      │
  │                                                                           │
  └───────────────────────────────────────────────────────────────────────────┘

  To find alice's groups, Vault searches:

      Base:   ou=groups,dc=example,dc=com
      Filter: (member=uid=alice,ou=users,dc=example,dc=com)
                      ▲
                      └── This is {{.UserDN}} in the groupfilter
```

### Important: No Native Nested Group Support

Unlike Active Directory, OpenLDAP does NOT have native nested group resolution.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  OPENLDAP NESTED GROUP LIMITATION                                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  If you have:                                                                   │
│                                                                                 │
│  ┌──────────────────┐                                                          │
│  │  super-admins    │ ◄── Top-level group                                      │
│  │  member: vault-  │                                                          │
│  │          admins  │───┐                                                      │
│  └──────────────────┘   │ (vault-admins is a member)                           │
│                         ▼                                                      │
│  ┌──────────────────┐                                                          │
│  │  vault-admins    │ ◄── Group containing users                               │
│  │  member: alice   │                                                          │
│  └──────────────────┘                                                          │
│                                                                                 │
│  Query for alice's groups returns: vault-admins                                 │
│  NOT super-admins (nested groups not followed)                                  │
│                                                                                 │
│  WORKAROUND: Add users directly to all groups they need access to              │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## OpenLDAP vs Active Directory

If you're familiar with Active Directory, here's what's different with OpenLDAP:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    KEY CONFIGURATION DIFFERENCES                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│  userattr                                                                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  OpenLDAP uses:   uid              (POSIX standard)                             │
│  AD uses:         sAMAccountName   (Windows legacy)                             │
│                                                                                 │
│  WHY: OpenLDAP follows POSIX/Unix conventions where 'uid' is the standard       │
│       username attribute. AD uses its own Windows-specific attribute.           │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│  Container Naming                                                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  OpenLDAP uses:   ou=users,dc=...      (Organizational Unit)                    │
│  AD uses:         CN=Users,DC=...      (Common Name container)                  │
│                                                                                 │
│  WHY: OpenLDAP typically organizes entries in OUs (ou=). AD's default           │
│       "Users" container is a CN, not an OU. Custom folders in AD are OUs.       │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│  Bind Format                                                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  OpenLDAP uses:   cn=admin,dc=example,dc=com   (Full DN)                        │
│  AD uses:         admin@example.com             (UPN - email style)             │
│                                                                                 │
│  WHY: OpenLDAP requires full DNs for binding. AD supports the more              │
│       convenient UPN (User Principal Name) format.                              │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│  Group Filter                                                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  OpenLDAP:   (member={{.UserDN}})                                               │
│  AD:         (&(objectClass=group)(member:1.2.840.113556.1.4.1941:={{.UserDN}}))│
│                                                                                 │
│  WHY: AD includes a special OID for recursive nested group lookup.              │
│       OpenLDAP doesn't support this OID - use simple member filter.             │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Quick Comparison Table

| Parameter | OpenLDAP | Active Directory |
|-----------|----------|------------------|
| `userattr` | `uid` | `sAMAccountName` |
| `userdn` | `ou=users,dc=...` | `CN=Users,DC=...` |
| `binddn` format | Full DN | UPN (`user@domain`) |
| `groupfilter` | `(member={{.UserDN}})` | Includes OID for nesting |
| Nested groups | Not supported | Supported via OID |

---

## Security Considerations

### LDAP vs LDAPS

```
┌────────────────────────────────────────────────────────────────────────────────┐
│  Port 389 (LDAP)              vs           Port 636 (LDAPS)                    │
├────────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  ┌──────────────────────┐                 ┌──────────────────────┐            │
│  │  Vault ──── OpenLDAP │                 │  Vault ════ OpenLDAP │            │
│  │        plaintext     │                 │        encrypted     │            │
│  └──────────────────────┘                 └──────────────────────┘            │
│                                                                                │
│  • Credentials visible on network         • All traffic encrypted              │
│  • OK for same-VPC/trusted network        • Required for untrusted networks   │
│  • Simpler setup (no certs)               • Requires SSL/TLS certificates     │
│                                                                                │
│  For production across untrusted networks, use LDAPS (port 636)                │
│  or StartTLS on port 389                                                       │
│                                                                                │
└────────────────────────────────────────────────────────────────────────────────┘
```

### Service Account Best Practices

```
┌────────────────────────────────────────────────────────────────────────────────┐
│  SERVICE ACCOUNT RECOMMENDATIONS                                               │
├────────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  DO:                                                                           │
│  ✓ Create a dedicated service account (don't reuse admin account)             │
│  ✓ Give it only READ permissions to ou=users and ou=groups                    │
│  ✓ Use a strong, unique password                                              │
│  ✓ Store the password securely (in Vault after initial setup!)                │
│  ✓ Document the account purpose                                               │
│                                                                                │
│  DON'T:                                                                        │
│  ✗ Give admin/write privileges                                                │
│  ✗ Use the same account for other applications                                │
│  ✗ Store password in plain text config files                                  │
│                                                                                │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## Quick Reference Card

### Configuration Parameters

| Parameter | Purpose | Typical OpenLDAP Value | Troubleshooting Phase |
|-----------|---------|------------------------|----------------------|
| `url` | Server location | `ldap://<IP>:389` | Phase 1: Connectivity |
| `binddn` | Service account | `cn=admin,dc=...` | Phase 2: Service Bind |
| `bindpass` | Service password | (secret) | Phase 2: Service Bind |
| `userdn` | Where to find users | `ou=users,dc=...` | Phase 3: User Discovery |
| `userattr` | Username attribute | `uid` | Phase 3: User Discovery |
| `groupdn` | Where to find groups | `ou=groups,dc=...` | Phase 5: Group Resolution |
| `groupattr` | Group name attribute | `cn` | Phase 5: Group Resolution |
| `groupfilter` | How to find groups | `(member={{.UserDN}})` | Phase 5: Group Resolution |

### Common Ports

| Port | Protocol | Use |
|------|----------|-----|
| 389 | LDAP | Standard unencrypted |
| 636 | LDAPS | SSL/TLS encrypted |

### Vault Commands Reference

```bash
# Enable LDAP auth method
vault auth enable ldap

# Configure LDAP connection
vault write auth/ldap/config \
    url="ldap://<LDAP_SERVER>:389" \
    binddn="cn=admin,dc=<DOMAIN>,dc=<TLD>" \
    bindpass="<PASSWORD>" \
    userdn="ou=users,dc=<DOMAIN>,dc=<TLD>" \
    userattr="uid" \
    groupdn="ou=groups,dc=<DOMAIN>,dc=<TLD>" \
    groupattr="cn" \
    groupfilter="(member={{.UserDN}})"

# Create group mapping
vault write auth/ldap/groups/<GROUP_NAME> \
    policies="<POLICY_NAME>"

# Test login
vault login -method=ldap username=<USERNAME>
```

---

## See Also

- **[Troubleshooting Guide](troubleshooting.md)** - Diagnose and fix authentication issues
- **[HashiCorp LDAP Auth Docs](https://developer.hashicorp.com/vault/docs/auth/ldap)** - Official documentation
