# Vault Replication - Understanding the Flow

This document explains how Vault replication works, the differences between DR and Performance replication, and the data flow between clusters.

## Replication Overview

```
                         VAULT REPLICATION ARCHITECTURE
+------------------------------------------------------------------------+
|                                                                        |
|   PRIMARY CLUSTER                         SECONDARY CLUSTER            |
|   +-----------------+                     +-----------------+          |
|   |                 |                     |                 |          |
|   |  +-----------+  |                     |  +-----------+  |          |
|   |  |  Leader   |  |     Replication     |  |  Leader   |  |          |
|   |  |  (Active) |  | ==================> |  | (Standby) |  |          |
|   |  +-----------+  |     Stream          |  +-----------+  |          |
|   |       |         |                     |       |         |          |
|   |   +---+---+     |                     |   +---+---+     |          |
|   |   |   |   |     |                     |   |   |   |     |          |
|   |  S1  S2  S3     |                     |  S1  S2  S3     |          |
|   |                 |                     |                 |          |
|   +-----------------+                     +-----------------+          |
|                                                                        |
|   S = Standby node within cluster                                      |
|                                                                        |
+------------------------------------------------------------------------+
```

## DR Replication vs Performance Replication

### DR (Disaster Recovery) Replication

```
DR REPLICATION FLOW
+-------------------+                     +-------------------+
|     PRIMARY       |                     |    SECONDARY      |
|                   |                     |                   |
|  Clients -------> |   Full Data Sync    |    (STANDBY)      |
|  All Operations   | ==================> |   No Clients      |
|                   |                     |   No Auth         |
|  - Reads          |   Everything        |   Root Token      |
|  - Writes         |   Replicated        |   Invalidated     |
|  - Auth           |                     |                   |
+-------------------+                     +-------------------+
         |                                         |
         |                                         |
    ACTIVE CLUSTER                        PASSIVE STANDBY
    Serves all traffic                    Only for disaster
```

**Characteristics:**
- Full copy of all data, configuration, and state
- Secondary is completely passive (cannot serve requests)
- Root token on secondary is invalidated
- Used for disaster recovery scenarios
- Requires DR operation token to promote secondary

### Performance Replication

```
PERFORMANCE REPLICATION FLOW
+-------------------+                     +-------------------+
|     PRIMARY       |                     |    SECONDARY      |
|                   |                     |                   |
|  Writes --------> |   Data Replication  |  <------- Reads   |
|                   | ==================> |                   |
|  - New secrets    |   - Secrets         |  - Read secrets   |
|  - Updates        |   - Policies        |  - Auth (local)   |
|  - Config changes |   - Auth config     |  - Local tokens   |
|                   |   - Identities      |                   |
+-------------------+                     +-------------------+
         |                                         |
         |                                         |
    WRITE REQUESTS                         READ REQUESTS
    Go to Primary                         Served Locally


                   WRITE FORWARDING
+-------------------+                     +-------------------+
|     PRIMARY       |                     |    SECONDARY      |
|                   |                     |                   |
|  <~~~~~~~~~~~~~~~~|   Write Forward     |  <-- Client Write |
|                   | <~~~~~~~~~~~~~~~~   |                   |
|  Process Write    |                     |  Forwards to      |
|  Replicate -------|-------------------->|  Primary          |
+-------------------+                     +-------------------+
```

**Characteristics:**
- Data is replicated, but tokens and leases are local
- Secondary can serve read requests (reduces primary load)
- Writes are forwarded to primary, then replicated back
- Secondary maintains its own token store
- Root token on secondary is retained

## What Gets Replicated

### DR Replication - Everything

| Data Type | Replicated? |
|-----------|-------------|
| Secrets engine data | Yes |
| Auth method config | Yes |
| Policies | Yes |
| Tokens | Yes |
| Leases | Yes |
| Identity entities | Yes |
| Groups | Yes |
| Audit config | Yes |

### Performance Replication - Most Things

| Data Type | Replicated? | Notes |
|-----------|-------------|-------|
| Secrets engine data | Yes | |
| Auth method config | Yes | |
| Policies | Yes | |
| Identity entities | Yes | |
| Groups | Yes | |
| **Tokens** | **No** | Local to each cluster |
| **Leases** | **No** | Local to each cluster |
| Local mounts | No | Created with local=true |

## Token and Lease Behavior (Performance Replication)

```
TOKEN LIFECYCLE IN PERFORMANCE REPLICATION
+-------------------+                     +-------------------+
|     PRIMARY       |                     |    SECONDARY      |
|                   |                     |                   |
|  Token Store A    |                     |  Token Store B    |
|  +-------------+  |                     |  +-------------+  |
|  | Token 1     |  |                     |  | Token X     |  |
|  | Token 2     |  |   NOT REPLICATED    |  | Token Y     |  |
|  | Token 3     |  |                     |  | Token Z     |  |
|  +-------------+  |                     |  +-------------+  |
|                   |                     |                   |
|  A user can       |                     |  Same user can    |
|  authenticate     |                     |  authenticate     |
|  and get Token 1  |                     |  and get Token X  |
+-------------------+                     +-------------------+

WHY? Each cluster manages its own:
- Token creation and renewal
- Lease tracking and revocation
- This allows clusters to operate independently for reads
```

## Replication Ports

```
NETWORK CONNECTIVITY REQUIREMENTS
+-------------------+                     +-------------------+
|     PRIMARY       |                     |    SECONDARY      |
|                   |                     |                   |
|       :8200 <-----|---------------------|----> :8200        |
|   (API/Control)   |   Bidirectional     |   (API/Control)   |
|                   |                     |                   |
|       :8201 <-----|---------------------|----> :8201        |
|   (Cluster/Data)  |   Bidirectional     |   (Cluster/Data)  |
|                   |                     |                   |
+-------------------+                     +-------------------+

Port 8200: API requests and replication control
Port 8201: Cluster communication and data replication stream
```

## Replication Setup Flow

### DR Replication Setup

```
STEP-BY-STEP: DR REPLICATION SETUP

1. ENABLE PRIMARY
   PRIMARY$ vault write -f sys/replication/dr/primary/enable

   Result: Primary enters "dr_primary" mode

2. GENERATE SECONDARY TOKEN
   PRIMARY$ vault write sys/replication/dr/primary/secondary-token \
            id="dr-secondary"

   Result: Wrapped token for secondary activation

3. ENABLE SECONDARY
   SECONDARY$ vault write sys/replication/dr/secondary/enable \
              token="<wrapped-token>" \
              primary_api_addr="http://primary:8200"

   Result:
   - Secondary enters "dr_secondary" mode
   - Data sync begins
   - Root token invalidated on secondary

4. VERIFY
   PRIMARY$ vault read sys/replication/dr/status
   SECONDARY$ vault read sys/replication/dr/status
```

### Performance Replication Setup

```
STEP-BY-STEP: PERFORMANCE REPLICATION SETUP

1. ENABLE PRIMARY
   PRIMARY$ vault write -f sys/replication/performance/primary/enable

2. GENERATE SECONDARY TOKEN
   PRIMARY$ vault write sys/replication/performance/primary/secondary-token \
            id="perf-secondary"

3. ENABLE SECONDARY
   SECONDARY$ vault write sys/replication/performance/secondary/enable \
              token="<wrapped-token>" \
              primary_api_addr="http://primary:8200"

4. VERIFY
   PRIMARY$ vault read sys/replication/performance/status
   SECONDARY$ vault read sys/replication/performance/status
```

## DR Failover Process

```
DR FAILOVER SEQUENCE

BEFORE FAILOVER:
+-------------------+                     +-------------------+
|     PRIMARY       |        ACTIVE       |    SECONDARY      |
|     (Active)      | ==================> |    (Standby)      |
+-------------------+                     +-------------------+

PRIMARY GOES DOWN:
+-------------------+                     +-------------------+
|     PRIMARY       |                     |    SECONDARY      |
|     (DOWN)        |         X           |    (Standby)      |
+-------------------+                     +-------------------+

PROMOTE SECONDARY:
1. Generate DR operation token (requires recovery keys)
   SECONDARY$ vault operator generate-root -dr-token

2. Promote to primary
   SECONDARY$ vault write -f sys/replication/dr/secondary/promote \
              dr_operation_token="<dr-token>"

AFTER FAILOVER:
+-------------------+                     +-------------------+
|     PRIMARY       |                     |    SECONDARY      |
|     (DOWN)        |                     |    (Now PRIMARY)  |
+-------------------+                     +-------------------+

RESTORE OLD PRIMARY AS SECONDARY (later):
OLD-PRIMARY$ vault write sys/replication/dr/secondary/enable \
             token="<new-secondary-token>"
```

## Common Commands Reference

```bash
# Check overall replication status
vault read sys/replication/status

# Check DR status
vault read sys/replication/dr/status

# Check Performance status
vault read sys/replication/performance/status

# List connected secondaries (from primary)
vault read sys/replication/dr/status
vault read sys/replication/performance/status

# Revoke a secondary (from primary)
vault write sys/replication/dr/primary/revoke-secondary id="<secondary-id>"
vault write sys/replication/performance/primary/revoke-secondary id="<secondary-id>"

# Disable replication
# On Primary:
vault write -f sys/replication/dr/primary/disable
vault write -f sys/replication/performance/primary/disable
# On Secondary (makes it standalone):
vault write -f sys/replication/dr/secondary/disable
vault write -f sys/replication/performance/secondary/disable
```

## Related Documentation

- [Troubleshooting Guide](troubleshooting.md) - Common issues and solutions
- [HashiCorp Vault Replication Docs](https://developer.hashicorp.com/vault/docs/enterprise/replication)
