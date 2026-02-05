# Vault Cluster Secondary

This folder deploys a second Vault Enterprise cluster for DR and Performance Replication testing with the primary cluster (`awskms-autounseal/`).

**Prerequisites**: The primary Vault cluster in `awskms-autounseal/` must be deployed and initialized first.

## Architecture

```
┌─────────────────────────────────────┬────────────────────────────────────────────┐
│       PRIMARY CLUSTER VPC           │        SECONDARY CLUSTER VPC               │
│          10.0.0.0/16                │           10.1.0.0/16                      │
│                                     │                                            │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐│  ┌─────────┐ ┌─────────┐ ┌─────────┐      │
│  │ vault-1 │ │ vault-2 │ │ vault-3 ││  │ vault-1 │ │ vault-2 │ │ vault-3 │      │
│  └────┬────┘ └────┬────┘ └────┬────┘│  └────┬────┘ └────┬────┘ └────┬────┘      │
│       └──────────┼──────────┘      │       └──────────┼──────────┘             │
│            ┌─────┴─────┐           │            ┌─────┴─────┐                  │
│            │    NLB    │           │            │    NLB    │                  │
│            └───────────┘           │            └───────────┘                  │
└─────────────────────────────────┬──┴──┬───────────────────────────────────────-┘
                                  │     │
                            VPC Peering (Bidirectional)
                            Ports 8200 + 8201
```

## Deployment

### Step 1: Get Primary Cluster VPC ID

```bash
cd ../awskms-autounseal
terraform output vpc_id
```

### Step 2: Configure Secondary Cluster

```bash
cd ../vault-cluster-secondary
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your vault_license and primary_vpc_id
```

### Step 3: Deploy Secondary Cluster

```bash
terraform init
terraform apply -auto-approve
```

### Step 4: Initialize Secondary Cluster

```bash
./init.sh
```

### Step 5: Complete VPC Peering

The init script will output the VPC peering connection ID. Add it to the primary cluster:

```bash
cd ../awskms-autounseal
# Add to terraform.tfvars:
#   peer_vpc_peering_connection_id = "<id from secondary output>"
terraform apply
```

### Step 6: Verify Connectivity

```bash
cd ../vault-cluster-secondary
./scripts/verify-connectivity.sh
```

### Step 7: Enable Replication

Once connectivity is verified, enable desired replication either manually via Vault CLI or UI.

## Scripts

| Script | Description |
|--------|-------------|
| `init.sh` | Initialize the secondary Vault cluster |
| `scripts/verify-connectivity.sh` | Test cross-cluster connectivity |

## DR vs Performance Replication

| Aspect | DR Replication | Performance Replication |
|--------|----------------|------------------------|
| Secondary Role | Passive standby | Active read replica |
| Writes | Primary only | Primary only (forwarded) |
| Reads | Primary only | Both clusters |
| Tokens/Leases | Fully replicated | Local to each cluster (NOT replicated) |
| Root Token | Requires DR operation token | NOT valid (use recovery/unseal keys to generate new) |
| Re-auth after failover | No | Yes |
| Use Case | Disaster recovery | Geographic distribution |

## Troubleshooting

See `docs/troubleshooting.md` for common issues and solutions.

## Cleanup

**Recommended destroy order**: Primary first, then secondary.

The VPC peering has two sides - secondary is the requester (owns the connection), primary is the accepter. Destroying primary first ensures clean removal of peering-related resources while the connection still exists.

### Cleanest Approach

1. Remove `peer_vpc_peering_connection_id` from `awskms-autounseal/terraform.tfvars`
2. Run `terraform apply` in awskms-autounseal (removes accepter + route)
3. Destroy either cluster in any order:

```bash
# Destroy secondary cluster
cd vault-cluster-secondary
terraform destroy -auto-approve

# Destroy primary cluster (if desired)
cd ../awskms-autounseal
terraform destroy -auto-approve
```

This preserves flexibility - you can destroy just the secondary while keeping the primary intact.
