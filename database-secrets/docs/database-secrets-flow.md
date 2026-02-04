# Database Secrets Engine - Credential Lifecycle

This document explains how Vault's database secrets engine works across ALL database types. The flow is the same whether you're using PostgreSQL, MySQL, MongoDB, or any other supported database.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              VAULT                                       │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    Database Secrets Engine                         │  │
│  │                                                                    │  │
│  │   ┌────────────┐    ┌────────────┐    ┌────────────┐             │  │
│  │   │ Connection │    │   Roles    │    │   Leases   │             │  │
│  │   │   Config   │    │            │    │            │             │  │
│  │   └─────┬──────┘    └─────┬──────┘    └─────┬──────┘             │  │
│  │         │                 │                 │                     │  │
│  └─────────┼─────────────────┼─────────────────┼─────────────────────┘  │
│            │                 │                 │                        │
└────────────┼─────────────────┼─────────────────┼────────────────────────┘
             │                 │                 │
             ▼                 ▼                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           DATABASE                                       │
│                                                                          │
│     Admin credentials        CREATE user        REVOKE user             │
│     (stored in Vault)        on request         on TTL expire           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Core Concepts

### 1. Connection Configuration

Vault stores admin credentials to manage the database. This is configured once per database.

```
vault write database/<db>/config/<name>
├── connection_url   # How to connect to the database
├── username         # Admin user (stored encrypted)
├── password         # Admin password (stored encrypted)
└── allowed_roles    # Which roles can use this connection
```

### 2. Roles

Roles define WHAT credentials to create. Each role has:
- **Creation statements** - SQL/commands to create the user
- **Revocation statements** - SQL/commands to delete the user
- **TTL settings** - How long credentials are valid

### 3. Leases

Every generated credential gets a **lease** - Vault's way of tracking temporary credentials.

```
Lease ID: database/postgresql/creds/readonly/abc123
├── credential_id    # Reference to the credential
├── ttl              # Time remaining (default: 1 hour)
├── max_ttl          # Maximum renewal time (default: 24 hours)
└── renewable        # Can this lease be renewed?
```

---

## Dynamic Credentials Flow

This is the most common use case: generate a new credential on-demand.

```
                        REQUEST PHASE
┌────────┐                                    ┌──────────┐
│ Client │ ── vault read database/x/creds/y ─▶│  Vault   │
└────────┘                                    └────┬─────┘
                                                   │
                        CREATION PHASE             │
                                                   ▼
┌──────────┐                               ┌──────────────┐
│ Database │◀── CREATE USER 'v-...' ───────│    Vault     │
│          │    WITH PASSWORD '...'        │  (executes   │
│          │    VALID UNTIL '...'          │  creation    │
│          │                               │  statements) │
└──────────┘                               └──────┬───────┘
                                                  │
                        RESPONSE PHASE            │
┌────────┐                                        │
│ Client │◀── username: v-token-readonly-abc ────┘
│        │    password: <random>
│        │    lease_id: database/x/creds/y/xyz
│        │    lease_duration: 3600s
└────────┘

                        USAGE PHASE
┌────────┐                               ┌──────────┐
│ Client │ ── connect with credentials ─▶│ Database │
└────────┘                               └──────────┘

                        EXPIRATION PHASE
┌──────────┐    (after TTL expires)      ┌──────────────┐
│ Database │◀── DROP USER 'v-...' ───────│    Vault     │
│          │                             │  (executes   │
│          │                             │  revocation  │
│          │                             │  statements) │
└──────────┘                             └──────────────┘
```

### Timeline

```
Time ────────────────────────────────────────────────────────────────▶

t=0           t=0+ε                 t=TTL               t=max_ttl
│             │                     │                    │
▼             ▼                     ▼                    ▼
┌─────────────┬─────────────────────┬────────────────────┐
│   CREATE    │      VALID          │     REVOKED        │
│ credential  │   (usable)          │  (no longer works) │
└─────────────┴─────────────────────┴────────────────────┘

              ├── vault lease renew ─┤
                  (extends TTL up to max_ttl)
```

---

## Static Role Rotation Flow

For credentials that cannot be dynamically created (e.g., application service accounts).

```
                     CONFIGURATION PHASE (once)
┌─────────┐                                    ┌──────────┐
│  Admin  │ ── vault write database/x/        │  Vault   │
│         │    static-roles/myapp             │          │
│         │    db_name=x username=appuser     │          │
│         │    rotation_period=24h            │          │
└─────────┘                                   └────┬─────┘
                                                   │
                     ROTATION PHASE (scheduled)    │
                                                   ▼
┌──────────┐                               ┌──────────────┐
│ Database │◀── ALTER USER 'appuser'  ─────│    Vault     │
│          │    PASSWORD 'new-random'      │  (scheduled  │
│          │                               │   rotation)  │
└──────────┘                               └──────┬───────┘
                                                  │
                     RETRIEVAL PHASE              │
┌─────────┐                                       │
│  App    │ ── vault read database/x/     ───────┘
│         │    static-creds/myapp
│         │
│         │◀── username: appuser
│         │    password: <current rotated password>
└─────────┘
```

### Key Difference from Dynamic

| Aspect | Dynamic Credentials | Static Roles |
|--------|---------------------|--------------|
| User creation | Vault creates new users | You provide existing user |
| User lifecycle | Created and destroyed | Exists permanently |
| Password | Generated once, then revoked | Rotated periodically |
| Use case | Short-lived access | Long-running applications |

---

## Root Credential Rotation Flow

Rotate the admin credentials Vault uses to connect to the database.

```
┌─────────┐                                    ┌──────────┐
│  Admin  │ ── vault write database/x/        │  Vault   │
│         │    rotate-root/mydb               └────┬─────┘
└─────────┘                                        │
                                                   ▼
┌──────────┐                               ┌──────────────┐
│ Database │◀── ALTER USER 'vault_admin' ──│    Vault     │
│          │    PASSWORD 'new-random'      │  (changes    │
│          │                               │   its own    │
│          │                               │   password)  │
└──────────┘                               └──────────────┘

IMPORTANT: After rotation, Vault knows the new password,
but YOU don't. This is intentional for security.
```

---

## Lease Management

### Renewing a Lease

Extends the TTL without creating new credentials:

```bash
vault lease renew database/postgresql/creds/readonly/abc123
```

### Revoking a Lease

Immediately deletes the credential from the database:

```bash
vault lease revoke database/postgresql/creds/readonly/abc123
```

### Revoking All Leases (Prefix)

Revoke all credentials for a specific role:

```bash
vault lease revoke -prefix database/postgresql/creds/readonly
```

---

## Common Verification Commands

These commands work for ALL database types:

```bash
# List configured databases
vault list database/config

# Read connection configuration (credentials redacted)
vault read database/<db>/config/<name>

# List available roles
vault list database/<db>/roles

# Read role definition
vault read database/<db>/roles/<role>

# Generate dynamic credentials
vault read database/<db>/creds/<role>

# Check lease status
vault lease lookup <lease_id>

# List active leases
vault list sys/leases/lookup/database/<db>/creds/<role>
```

---

## Security Model

```
┌─────────────────────────────────────────────────────────────┐
│                    CREDENTIAL HIERARCHY                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  ROOT/ADMIN CREDENTIALS                              │   │
│  │  - Stored encrypted in Vault                         │   │
│  │  - Can be rotated (then Vault holds new password)    │   │
│  │  - Used ONLY by Vault to create/revoke users         │   │
│  └──────────────────────────────────────────────────────┘   │
│                           │                                  │
│                           ▼                                  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  DYNAMIC CREDENTIALS                                 │   │
│  │  - Created on-demand with limited privileges         │   │
│  │  - Short-lived (TTL controlled)                      │   │
│  │  - Automatically revoked on expiration               │   │
│  │  - Unique per request (no credential sharing)        │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Related Documentation

- [Troubleshooting](troubleshooting.md) - Common issues and decision trees
- [Official Vault Database Secrets Docs](https://developer.hashicorp.com/vault/docs/secrets/databases)
