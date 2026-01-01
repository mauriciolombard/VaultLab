# AWS KMS Auto-Unseal Vault Cluster

This Terraform configuration creates a 3-node Vault Enterprise cluster with AWS KMS auto-unseal.

## Architecture

- **3 Vault Enterprise nodes** across 3 Availability Zones
- **Raft storage** for HA and data replication
- **AWS KMS** for automatic unsealing
- **Network Load Balancer** for high availability access
- **EC2 auto-join** for cluster formation

## Prerequisites

1. **Terraform** >= 1.0.0
2. **AWS credentials** via Doormat (temporary credentials)
3. **Vault Enterprise license**

## Quick Start

### 1. Set AWS Credentials (via Doormat)

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
```

### 2. Create terraform.tfvars (Likely this step is required only the first time running through the lab)

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set:
- `vault_license` - Your Vault Enterprise license string
- `vault_version` - Desired Vault version (e.g., "1.19.12+ent")
- Optionally adjust other variables

### 3. Deploy

```bash
terraform init
terraform apply -auto-approve
```

### 4. Initialize Vault

After deployment, initialize the cluster using the provided script. Make sure Vault CLI is installed https://developer.hashicorp.com/vault/tutorials/get-started/install-binary#vault-enterprise

```bash
./init.sh
```

This script will:
- Initialize Vault on the first node
- Save the recovery keys and root token to `vault-init-keys.json`
- Join the other nodes to the Raft cluster

**Important:** Save the contents of `vault-init-keys.json` securely - it contains your recovery keys and initial root token.

### 5. Once the cluster is initialized and healthy - export the generated VAULT_ADDR and VAULT_TOKEN

Alternatively:

```bash
# Get the export command from outputs
terraform output export_vault_addr

# Example:
export VAULT_ADDR=http://vaultlab-nlb-xxxxx.elb.us-east-1.amazonaws.com:8200

# Verify
vault status
```

## Accessing Individual Nodes

To get the SSH commands for each node:

```bash
terraform output ssh_connection_commands
```

Or get the instance IPs:

```bash
terraform output vault_instance_ips
```

General SSH command format is:
```bash
ssh -i vault-key.pem ec2-user@<PUBLIC_IP>
```


### Vault Config File Locations

On each node, configuration file at:
```
/etc/vault.d/vault.hcl
```

License file is at:
```
/etc/vault.d/vault.hclic
```

### Common Node Operations

Once connected to a node:

```bash
# View the config
sudo cat /etc/vault.d/vault.hcl

# Check Vault status on that specific node
export VAULT_ADDR=http://127.0.0.1:8200
vault status

# View Vault logs
sudo journalctl -u vault -f
```

If you are debugging Vault issues, you will often see `--no-pager` combined with these flags:

- `--since "1 hour ago"`: Only shows logs from the last hour (prevents dumping millions of lines)
  - Example: `journalctl -u vault --since "10 min ago" --no-pager`
- `-n 50`: Shows only the last 50 lines (most recent entries)
  - Example: `journalctl -u vault -n 50 --no-pager`
- `-f`: "Follow" mode (like `tail -f`). This actually ignores `--no-pager` because it is inherently interactive, streaming new logs as they arrive

## To Upgrade Vault

On each Vault node:

```bash
sudo dnf install -y vault-enterprise-1.21.1+ent
sudo systemctl restart vault
```

## Cleanup

When the cluster is no longer needed, destroy all AWS resources:

```bash
# Preview what will be destroyed
terraform plan -destroy

# Destroy all resources (will prompt for confirmation)
terraform destroy

# Or skip confirmation prompt
terraform destroy -auto-approve
```

**Note:** This will delete:
- All 3 EC2 instances
- The Network Load Balancer
- The KMS key
- VPC and all networking components
- Security groups
- The local `vault-key.pem` SSH key will remain (delete manually if needed)