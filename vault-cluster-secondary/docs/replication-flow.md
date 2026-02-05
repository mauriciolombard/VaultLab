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
- Primary's root token is NOT valid on secondary (use recovery/unseal keys to generate new)

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

## DR Failover Process

See: [https://support.hashicorp.com/hc/en-us/articles/360001921007-Vault-CLI-Guide-to-Disaster-Recovery-Replication-Failover](https://support.hashicorp.com/hc/en-us/articles/360001921007-Vault-CLI-Guide-to-Disaster-Recovery-Replication-Failover)

## Related Documentation

- [Troubleshooting Guide](troubleshooting.md) - Common issues and solutions
- [HashiCorp Vault Replication Docs](https://developer.hashicorp.com/vault/docs/enterprise/replication)
