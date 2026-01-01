#!/bin/bash
# Vault Cluster Initialization Script
# This script initializes the Vault cluster after Terraform deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_OUTPUT_FILE="${SCRIPT_DIR}/vault-init-keys.json"

echo "=== Vault Cluster Initialization ==="
echo ""

# Get VAULT_ADDR from Terraform output
echo "Retrieving NLB address from Terraform..."
cd "$SCRIPT_DIR"

VAULT_ADDR=$(terraform output -raw vault_addr 2>/dev/null)
if [ -z "$VAULT_ADDR" ]; then
    echo "ERROR: Could not get vault_addr from Terraform outputs."
    echo "Make sure you have run 'terraform apply' successfully."
    exit 1
fi

export VAULT_ADDR
echo "VAULT_ADDR set to: $VAULT_ADDR"
echo ""

# Wait for Vault to be ready
echo "Waiting for Vault to be reachable..."
MAX_RETRIES=30
RETRY_INTERVAL=10
RETRIES=0

while [ $RETRIES -lt $MAX_RETRIES ]; do
    if vault status 2>&1 | grep -q "Initialized"; then
        echo "Vault is reachable!"
        break
    fi
    RETRIES=$((RETRIES + 1))
    echo "  Attempt $RETRIES/$MAX_RETRIES - Vault not ready yet, waiting ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

if [ $RETRIES -eq $MAX_RETRIES ]; then
    echo "ERROR: Vault did not become reachable after $((MAX_RETRIES * RETRY_INTERVAL)) seconds."
    echo "Check that:"
    echo "  - The EC2 instances are running"
    echo "  - The NLB health checks are passing"
    echo "  - Security groups allow access"
    exit 1
fi

echo ""

# Check if Vault is already initialized
VAULT_STATUS=$(vault status -format=json 2>/dev/null || echo '{}')
IS_INITIALIZED=$(echo "$VAULT_STATUS" | grep -o '"initialized":[^,}]*' | cut -d: -f2 | tr -d ' ')

if [ "$IS_INITIALIZED" = "true" ]; then
    echo "Vault is already initialized."
    echo ""
    vault status
    exit 0
fi

# Initialize Vault
echo "Initializing Vault cluster..."
echo "  (Using AWS KMS auto-unseal - will generate recovery keys)"
echo ""

if vault operator init -format=json > "$INIT_OUTPUT_FILE" 2>&1; then
    echo "Vault initialized successfully!"
    echo ""
    echo "=== IMPORTANT: SAVE THESE CREDENTIALS ==="
    echo ""

    # Display recovery keys
    echo "Recovery Keys:"
    jq -r '.recovery_keys_b64 | to_entries[] | "  Key \(.key + 1): \(.value)"' "$INIT_OUTPUT_FILE"
    echo ""

    # Display root token
    ROOT_TOKEN=$(jq -r '.root_token' "$INIT_OUTPUT_FILE")
    echo "Initial Root Token: $ROOT_TOKEN"
    echo ""

    echo "Credentials saved to: $INIT_OUTPUT_FILE"
    echo ""
    echo "WARNING: Store these credentials securely and delete $INIT_OUTPUT_FILE"
    echo "         The recovery keys are needed for certain recovery operations."
    echo ""

    # Set restrictive permissions on the keys file
    chmod 600 "$INIT_OUTPUT_FILE"

    # Wait a moment for the cluster to stabilize
    echo "Waiting for cluster to stabilize..."
    sleep 5

    # Show final status
    echo ""
    echo "=== Vault Status ==="
    vault status

    echo ""
    echo "=== Raft Peer Status ==="
    VAULT_TOKEN="$ROOT_TOKEN" vault operator raft list-peers 2>/dev/null || echo "(Peers may take a moment to join)"

    echo ""
    echo "=== Enabling Audit Device ==="
    if VAULT_TOKEN="$ROOT_TOKEN" vault audit enable file file_path=/var/log/vault/audit.log 2>/dev/null; then
        echo "File audit device enabled at /var/log/vault/audit.log"
    else
        echo "WARNING: Could not enable audit device (may already be enabled)"
    fi

    echo ""
    echo "=== Quick Start Commands ==="
    echo ""
    echo "Export these variables to interact with the cluster:"
    echo ""
    echo "  export VAULT_ADDR=$VAULT_ADDR"
    echo "  export VAULT_TOKEN=$ROOT_TOKEN"
    echo ""
else
    echo "ERROR: Failed to initialize Vault."
    cat "$INIT_OUTPUT_FILE" 2>/dev/null
    rm -f "$INIT_OUTPUT_FILE"
    exit 1
fi
