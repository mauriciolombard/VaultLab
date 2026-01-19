# Vault Active Directory Authentication Flow

## Overview

This document provides a mental map of how Vault LDAP authentication works with Microsoft Active Directory, including key configuration differences from standard OpenLDAP.

## Authentication Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                  VAULT LDAP AUTHENTICATION FLOW (Active Directory)          │
└─────────────────────────────────────────────────────────────────────────────┘

                    ┌─────────────┐
                    │    User     │
                    │  (alice)    │
                    └──────┬──────┘
                           │
                           │ 1. vault login -method=ldap username=alice
                           │    (or username=alice@vaultlab.local with UPN)
                           ▼
                    ┌─────────────┐
                    │    Vault    │
                    │   Server    │
                    └──────┬──────┘
                           │
                           │ 2. Bind to AD using service account
                           │    binddn: vault-svc@vaultlab.local
                           ▼
                    ┌─────────────┐
                    │   Active    │
                    │  Directory  │
                    └──────┬──────┘
                           │
                           │ 3. Search for user in userdn (CN=Users,DC=...)
                           │    Filter: (sAMAccountName=alice)
                           │
                           │ 4. Found: CN=Alice Admin,CN=Users,DC=vaultlab,DC=local
                           ▼
                    ┌─────────────┐
                    │   Active    │
                    │  Directory  │
                    └──────┬──────┘
                           │
                           │ 5. Vault rebinds as user to verify password
                           │    Bind: alice@vaultlab.local or full DN
                           │
                           │ 6. Search for group membership using LDAP_MATCHING_RULE
                           │    Base: CN=Users,DC=vaultlab,DC=local
                           │    Filter: (&(objectClass=group)
                           │             (member:1.2.840.113556.1.4.1941:=<UserDN>))
                           │
                           │ 7. Found: Vault-Admins (nested group support via OID)
                           ▼
                    ┌─────────────┐
                    │    Vault    │
                    │   Server    │
                    └──────┬──────┘
                           │
                           │ 8. Map group "Vault-Admins" to policies
                           │    Group Config: Vault-Admins → [ldap-admins]
                           │
                           │ 9. Generate token with policies
                           ▼
                    ┌─────────────┐
                    │   Token     │
                    │ + policies  │
                    │ [ldap-admins│
                    │  default]   │
                    └─────────────┘
```

## Key Differences: Active Directory vs OpenLDAP

| Aspect | Active Directory | OpenLDAP |
|--------|-----------------|----------|
| **User Attribute** | `sAMAccountName` | `uid` |
| **User Container** | `CN=Users,DC=...` | `ou=users,dc=...` |
| **Bind Format** | `user@domain` (UPN) or DN | Full DN |
| **Group Membership** | `member` with OID for nested | `member` attribute |
| **Group Filter OID** | `1.2.840.113556.1.4.1941` | Not applicable |
| **Nested Groups** | Supported via LDAP_MATCHING_RULE | Manual recursion |

## Active Directory Structure

```
DC=vaultlab,DC=local                           # Domain root
├── CN=Users                                   # Default user container
│   ├── CN=Administrator                       # Built-in admin
│   ├── CN=vault-svc                          # Service account (binddn)
│   │   ├── sAMAccountName: vault-svc
│   │   └── userPrincipalName: vault-svc@vaultlab.local
│   ├── CN=Alice Admin                        # Test user
│   │   ├── sAMAccountName: alice
│   │   ├── userPrincipalName: alice@vaultlab.local
│   │   └── memberOf: CN=Vault-Admins,CN=Users,...
│   ├── CN=Bob User
│   │   └── memberOf: CN=Vault-Users,CN=Users,...
│   ├── CN=Charlie User
│   │   └── memberOf: CN=Vault-Users,CN=Users,...
│   ├── CN=Vault-Admins                       # Security group
│   │   ├── member: CN=Alice Admin,CN=Users,...
│   │   └── objectClass: group
│   └── CN=Vault-Users                        # Security group
│       ├── member: CN=Bob User,CN=Users,...
│       ├── member: CN=Charlie User,CN=Users,...
│       └── objectClass: group
└── CN=Computers                               # Computer accounts
```

## Key Configuration Parameters (AD-Specific)

| Parameter | AD Value | Description |
|-----------|----------|-------------|
| `url` | `ldap://10.0.1.50:389` | AD server IP:port |
| `binddn` | `vault-svc@vaultlab.local` | UPN format for service account |
| `userdn` | `CN=Users,DC=vaultlab,DC=local` | Container for users |
| `userattr` | `sAMAccountName` | Username attribute (NOT uid) |
| `upndomain` | `vaultlab.local` | Enables user@domain login |
| `groupdn` | `CN=Users,DC=vaultlab,DC=local` | Container for groups |
| `groupattr` | `cn` | Group name attribute |
| `groupfilter` | See below | AD-specific filter with OID |

### AD Group Filter Explained

```
(&(objectClass=group)(member:1.2.840.113556.1.4.1941:={{.UserDN}}))
```

- `objectClass=group` - Only search group objects
- `member:1.2.840.113556.1.4.1941:=` - LDAP_MATCHING_RULE_IN_CHAIN
  - This OID enables **nested group membership** queries
  - Recursively checks if user is member of any nested groups

## Vault Configuration Commands (AD)

### Enable LDAP Auth Method
```bash
vault auth enable ldap
```

### Configure for Active Directory
```bash
vault write auth/ldap/config \
    url="ldap://10.0.1.50:389" \
    binddn="vault-svc@vaultlab.local" \
    bindpass="VaultBind123!" \
    userdn="CN=Users,DC=vaultlab,DC=local" \
    userattr="sAMAccountName" \
    upndomain="vaultlab.local" \
    groupdn="CN=Users,DC=vaultlab,DC=local" \
    groupattr="cn" \
    groupfilter="(&(objectClass=group)(member:1.2.840.113556.1.4.1941:={{.UserDN}}))"
```

### Create Group Mappings (Case-Sensitive!)
```bash
vault write auth/ldap/groups/Vault-Admins \
    policies="ldap-admins"

vault write auth/ldap/groups/Vault-Users \
    policies="ldap-users"
```

### Test Login
```bash
# Using sAMAccountName
vault login -method=ldap username=alice password=Password123!

# Using UPN (if upndomain configured)
vault login -method=ldap username=alice@vaultlab.local password=Password123!
```

## AD-Specific Troubleshooting

### Common Issue: "User not found"

**Check userattr setting:**
```bash
# AD uses sAMAccountName, not uid
vault read auth/ldap/config | grep userattr
# Should show: userattr = sAMAccountName
```

**Test with ldapsearch:**
```bash
ldapsearch -x -H ldap://<AD_IP>:389 \
    -D "vault-svc@vaultlab.local" \
    -w "VaultBind123!" \
    -b "CN=Users,DC=vaultlab,DC=local" \
    "(sAMAccountName=alice)" dn
```

### Common Issue: "No groups found"

**Group names are CASE-SENSITIVE in Vault:**
```bash
# Wrong (lowercase)
vault write auth/ldap/groups/vault-admins policies="..."

# Correct (match AD group name exactly)
vault write auth/ldap/groups/Vault-Admins policies="..."
```

**Verify group membership in AD:**
```bash
ldapsearch -x -H ldap://<AD_IP>:389 \
    -D "vault-svc@vaultlab.local" \
    -w "VaultBind123!" \
    -b "CN=Users,DC=vaultlab,DC=local" \
    "(sAMAccountName=alice)" memberOf
```

### Common Issue: Service Account Cannot Bind

**Test bind manually:**
```bash
# UPN format (preferred for AD)
ldapsearch -x -H ldap://<AD_IP>:389 \
    -D "vault-svc@vaultlab.local" \
    -w "VaultBind123!" \
    -b "" -s base

# DN format (alternative)
ldapsearch -x -H ldap://<AD_IP>:389 \
    -D "CN=vault-svc,CN=Users,DC=vaultlab,DC=local" \
    -w "VaultBind123!" \
    -b "" -s base
```

## Vault-AD Group-to-Policy Mapping

```
┌──────────────────────┐       ┌────────────────────┐       ┌─────────────────┐
│    AD Group          │ ────▶ │ Vault Group Config │ ────▶ │ Vault Policy    │
│  (CN=Vault-Admins)   │       │  (Case-Sensitive!) │       │                 │
└──────────────────────┘       └────────────────────┘       └─────────────────┘

Vault-Admins    ────────▶   auth/ldap/groups/    ────────▶   ldap-admins
                            Vault-Admins                     (full access)

Vault-Users     ────────▶   auth/ldap/groups/    ────────▶   ldap-users
                            Vault-Users                      (read-only)
```

## AD Ports Reference

| Port | Protocol | Service |
|------|----------|---------|
| 389 | TCP/UDP | LDAP |
| 636 | TCP | LDAPS (SSL) |
| 3268 | TCP | Global Catalog |
| 3269 | TCP | Global Catalog SSL |
| 88 | TCP/UDP | Kerberos |
| 53 | TCP/UDP | DNS |
| 445 | TCP | SMB |
