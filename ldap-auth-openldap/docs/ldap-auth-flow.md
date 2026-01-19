# Vault LDAP Authentication Flow

## Overview

This document provides a mental map of how Vault LDAP authentication works, including the configuration parameters and authentication flow.

## Authentication Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        VAULT LDAP AUTHENTICATION FLOW                        │
└─────────────────────────────────────────────────────────────────────────────┘

                    ┌─────────────┐
                    │    User     │
                    │  (alice)    │
                    └──────┬──────┘
                           │
                           │ 1. vault login -method=ldap username=alice
                           ▼
                    ┌─────────────┐
                    │    Vault    │
                    │   Server    │
                    └──────┬──────┘
                           │
                           │ 2. Bind to LDAP using binddn/bindpass
                           │    (cn=admin,dc=vaultlab,dc=local)
                           ▼
                    ┌─────────────┐
                    │   OpenLDAP  │
                    │   Server    │
                    └──────┬──────┘
                           │
                           │ 3. Search for user in userdn
                           │    (ou=users,dc=vaultlab,dc=local)
                           │    Filter: (uid=alice)
                           │
                           │ 4. Found: uid=alice,ou=users,dc=vaultlab,dc=local
                           ▼
                    ┌─────────────┐
                    │   OpenLDAP  │
                    │   (rebind)  │
                    └──────┬──────┘
                           │
                           │ 5. Vault rebinds as user to verify password
                           │    Bind DN: uid=alice,ou=users,...
                           │    Password: user's password
                           │
                           │ 6. Search for group membership
                           │    Base: ou=groups,dc=vaultlab,dc=local
                           │    Filter: (member=uid=alice,ou=users,...)
                           │
                           │ 7. Found: cn=vault-admins
                           ▼
                    ┌─────────────┐
                    │    Vault    │
                    │   Server    │
                    └──────┬──────┘
                           │
                           │ 8. Map group "vault-admins" to policies
                           │    Group Config: vault-admins → [ldap-admins]
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

## Key Configuration Parameters

### LDAP Auth Method Configuration

| Parameter | Description | Example Value |
|-----------|-------------|---------------|
| `url` | LDAP server URL | `ldap://10.0.1.50:389` |
| `starttls` | Use STARTTLS | `false` |
| `binddn` | Service account DN for searches | `cn=admin,dc=vaultlab,dc=local` |
| `bindpass` | Service account password | `admin123` |
| `userdn` | Base DN for user searches | `ou=users,dc=vaultlab,dc=local` |
| `userattr` | Attribute for username | `uid` |
| `groupdn` | Base DN for group searches | `ou=groups,dc=vaultlab,dc=local` |
| `groupattr` | Attribute for group name | `cn` |
| `groupfilter` | LDAP filter for group lookup | `(member={{.UserDN}})` |

### User Authentication Process

1. **Initial Bind**: Vault binds to LDAP using the configured `binddn`/`bindpass`
2. **User Search**: Vault searches for the user under `userdn` using `userattr`
3. **User Bind**: Vault rebinds as the user to verify the password
4. **Group Search**: Vault searches `groupdn` for groups containing the user
5. **Policy Mapping**: Groups are mapped to Vault policies

## LDAP Directory Structure

```
dc=vaultlab,dc=local                    # Base DN
├── cn=admin                            # Admin (binddn)
├── ou=users                            # User container (userdn)
│   ├── uid=alice                       # User entry
│   │   ├── cn: Alice Admin
│   │   ├── uid: alice
│   │   ├── mail: alice@vaultlab.local
│   │   └── userPassword: {SSHA}...
│   ├── uid=bob
│   └── uid=charlie
└── ou=groups                           # Group container (groupdn)
    ├── cn=vault-admins                 # Group entry
    │   ├── cn: vault-admins
    │   └── member: uid=alice,ou=users,...
    └── cn=vault-users
        ├── cn: vault-users
        └── member: uid=bob,ou=users,...
            member: uid=charlie,ou=users,...
```

## Vault Group-to-Policy Mapping

```
┌──────────────────┐         ┌────────────────┐         ┌─────────────────┐
│   LDAP Group     │ ──────▶ │ Vault Group    │ ──────▶ │ Vault Policy    │
│   (cn=...)       │         │ Mapping        │         │                 │
└──────────────────┘         └────────────────┘         └─────────────────┘

vault-admins       ──────▶   auth/ldap/groups/  ──────▶  ldap-admins
                             vault-admins                 (full access)

vault-users        ──────▶   auth/ldap/groups/  ──────▶  ldap-users
                             vault-users                  (read-only)
```

## Configuration Commands Reference

### Enable LDAP Auth Method
```bash
vault auth enable ldap
```

### Configure LDAP Connection
```bash
vault write auth/ldap/config \
    url="ldap://10.0.1.50:389" \
    binddn="cn=admin,dc=vaultlab,dc=local" \
    bindpass="admin123" \
    userdn="ou=users,dc=vaultlab,dc=local" \
    userattr="uid" \
    groupdn="ou=groups,dc=vaultlab,dc=local" \
    groupattr="cn" \
    groupfilter="(member={{.UserDN}})"
```

### Create Group Mapping
```bash
vault write auth/ldap/groups/vault-admins \
    policies="ldap-admins"

vault write auth/ldap/groups/vault-users \
    policies="ldap-users"
```

### Test Login
```bash
vault login -method=ldap username=alice password=password123
```

## Troubleshooting Checklist

1. **Can Vault reach the LDAP server?**
   - Check network connectivity (port 389/636)
   - Verify security group rules

2. **Is the binddn/bindpass correct?**
   - Test with ldapsearch using same credentials

3. **Is the userdn correct?**
   - Ensure users exist under the specified OU

4. **Is the groupfilter correct?**
   - Test group membership queries with ldapsearch

5. **Are group mappings configured?**
   - Check `vault list auth/ldap/groups`
