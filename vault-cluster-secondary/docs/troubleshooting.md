# Vault Replication Troubleshooting Guide

This guide helps diagnose and resolve common issues with Vault replication.

## Troubleshooting Decision Tree

```
REPLICATION NOT WORKING?
          |
          v
+-------------------+
| Can clusters      |     NO     +------------------------+
| reach each other? |----------->| Check VPC Peering      |
| (ports 8200/8201) |            | Check Security Groups  |
+-------------------+            | Check Route Tables     |
          |                      +------------------------+
          | YES
          v
+-------------------+
| Is replication    |     NO     +------------------------+
| enabled on both   |----------->| Enable primary first   |
| clusters?         |            | Then enable secondary  |
+-------------------+            +------------------------+
          |
          | YES
          v
+-------------------+
| Does status show  |     NO     +------------------------+
| "connected"?      |----------->| Check activation token |
|                   |            | Verify primary_api_addr|
+-------------------+            +------------------------+
          |
          | YES
          v
+-------------------+
| Is data           |     NO     +------------------------+
| replicating?      |----------->| Check cluster_addr     |
|                   |            | Check port 8201        |
+-------------------+            +------------------------+
          |
          | YES
          v
     REPLICATION OK
```

## Phase 1: Network Connectivity Issues

### Symptom: Cannot connect to peer cluster

```bash
# Test connectivity from primary to secondary
nc -zv <SECONDARY_PRIVATE_IP> 8200
nc -zv <SECONDARY_PRIVATE_IP> 8201

# Test connectivity from secondary to primary
nc -zv <PRIMARY_PRIVATE_IP> 8200
nc -zv <PRIMARY_PRIVATE_IP> 8201
```

**Expected Result:** `Connection succeeded`

### Common Causes

| Issue | Check | Fix |
|-------|-------|-----|
| VPC peering inactive | `aws ec2 describe-vpc-peering-connections` | Accept peering request |
| Missing routes | Check route tables in AWS console | Add route to peer VPC |
| Security group rules | Check inbound rules allow peer CIDR | Add 8200/8201 from peer |
| Wrong IP used | Using public IP instead of private | Use private IPs for replication |

### VPC Peering Verification

```bash
# Check VPC peering status
aws ec2 describe-vpc-peering-connections \
  --query 'VpcPeeringConnections[*].[VpcPeeringConnectionId,Status.Code,RequesterVpcInfo.CidrBlock,AccepterVpcInfo.CidrBlock]' \
  --output table

# Expected: Status should be "active"
```

### Route Table Verification

```bash
# Check routes in primary VPC
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<PRIMARY_VPC_ID>" \
  --query 'RouteTables[*].Routes[*].[DestinationCidrBlock,VpcPeeringConnectionId]' \
  --output table

# Should see route to 10.1.0.0/16 via peering connection
```

## Phase 2: Replication Configuration Issues

### Symptom: Replication not enabled

```bash
# Check replication status
VAULT_ADDR="http://<CLUSTER_NLB>:8200" vault read sys/replication/status
```

**Expected Output:**
```
Key                     Value
---                     -----
dr                      map[mode:primary ...]
performance             map[mode:primary ...]
```

### Common Errors

#### "replication is already enabled"

```bash
# Disable existing replication first
vault write -f sys/replication/dr/primary/disable
# OR
vault write -f sys/replication/performance/primary/disable
```

#### "invalid secondary token"

Token may have expired (default TTL is short). Generate a new one:

```bash
# Generate new secondary token on primary
vault write sys/replication/dr/primary/secondary-token id="<SECONDARY_ID>"
```

#### "cluster addresses cannot be resolved"

Ensure `cluster_addr` in vault.hcl points to the correct private IP:

```hcl
cluster_addr = "http://<PRIVATE_IP>:8201"
```

## Phase 3: Replication Stream Issues

### Symptom: Connected but data not syncing

```bash
# Check detailed replication status
vault read sys/replication/dr/status
vault read sys/replication/performance/status
```

**Key Fields to Check:**

| Field | Good Value | Problem Value |
|-------|------------|---------------|
| `state` | `stream-wals` | `idle` or `initial-sync` stuck |
| `connection_state` | `connected` | `disconnected` |
| `last_wal` | Increasing | Stuck value |
| `merkle_root` | Matches primary | Mismatch |

### WAL Streaming Issues

```bash
# On primary - check WAL status
vault read sys/replication/dr/status

# Look for:
# - last_remote_wal: should be close to known_primary_cluster_addrs
# - merkle_root: should match between primary and secondary
```

## Phase 4: DR-Specific Issues

### Symptom: Cannot authenticate on DR secondary

**This is expected behavior.** DR secondaries invalidate the root token and cannot process authentication requests.

To access DR secondary:

```bash
# Generate DR operation token (requires recovery keys)
vault operator generate-root -dr-token -init

# Provide recovery keys
vault operator generate-root -dr-token -nonce=<NONCE>

# Decode the final token
vault operator generate-root -dr-token -decode=<ENCODED> -otp=<OTP>

# Use the DR operation token
VAULT_ADDR="http://<SECONDARY>:8200" vault login -method=token token=<DR_TOKEN>
```

### Symptom: DR promotion fails

```bash
# Check if secondary is in correct state for promotion
vault read sys/replication/dr/status

# state should be "stream-wals" for a healthy promotion
```

**Common Promotion Issues:**

| Error | Cause | Fix |
|-------|-------|-----|
| "not a dr secondary" | Wrong cluster | Verify VAULT_ADDR |
| "invalid dr operation token" | Token expired or wrong | Generate new token |
| "primary still reachable" | Primary not down | Use force option or wait |

## Phase 5: Performance-Specific Issues

### Symptom: Writes fail on secondary

**This is expected behavior.** Performance secondaries forward writes to primary.

If writes fail completely:

```bash
# Check primary connectivity from secondary
vault read sys/replication/performance/status

# Look for primary_cluster_addr and connection_state
```

### Symptom: Tokens from primary don't work on secondary

**This is expected behavior.** Performance secondaries have their own token store.

Users must authenticate on the cluster they want to use:

```bash
# Authenticate on secondary directly
VAULT_ADDR="http://<SECONDARY>:8200" vault login -method=<AUTH_METHOD>
```

## Common CLI Commands for Troubleshooting

### Status Commands

```bash
# Overall replication status
vault read sys/replication/status

# DR replication status
vault read sys/replication/dr/status

# Performance replication status
vault read sys/replication/performance/status

# Raft cluster status (each cluster)
vault operator raft list-peers
```

### Network Diagnostic Commands

```bash
# Test port connectivity
nc -zv <IP> 8200
nc -zv <IP> 8201

# Check DNS resolution (if using DNS names)
dig <HOSTNAME>

# Check VPC peering
aws ec2 describe-vpc-peering-connections

# Check security groups
aws ec2 describe-security-groups --group-ids <SG_ID>
```

### Log Analysis

```bash
# SSH to Vault instance and check logs
sudo journalctl -u vault -f

# Check audit log (if enabled)
sudo tail -f /var/log/vault/audit.log | jq
```

## Error Messages Reference

| Error | Meaning | Solution |
|-------|---------|----------|
| `connection refused` | Port not open or service down | Check security groups, verify Vault running |
| `no route to host` | Network path doesn't exist | Check VPC peering and route tables |
| `connection timed out` | Firewall blocking or routing issue | Check NACLs, security groups |
| `certificate verify failed` | TLS mismatch | Verify TLS config or disable for lab |
| `permission denied` | Token lacks permission | Use root token or correct policy |
| `replication is disabled` | Replication not enabled | Enable on primary first |
| `secondary token is invalid` | Token expired or wrong | Generate new token |

## Health Check Endpoints

```bash
# Basic health check
curl http://<VAULT_ADDR>:8200/v1/sys/health

# Response codes:
# 200 - initialized, unsealed, active
# 429 - unsealed, standby
# 472 - DR secondary
# 473 - performance standby
# 501 - not initialized
# 503 - sealed

# Detailed status
curl http://<VAULT_ADDR>:8200/v1/sys/health?standbyok=true
```

## Related Documentation

- [Replication Flow](replication-flow.md) - Understanding how replication works
- [HashiCorp Vault Troubleshooting](https://developer.hashicorp.com/vault/docs/troubleshooting)
