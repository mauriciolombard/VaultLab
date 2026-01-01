#!/bin/bash
# Initialize Vault and capture recovery keys and root token
# This script SSHs into the Vault instance and runs vault operator init

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Output file for credentials
INIT_OUTPUT_FILE="vault-init-keys.txt"

# Get Vault instance IP from terraform output
echo "Fetching Vault instance IP from Terraform..."
VAULT_IP=$(terraform output -raw vault_instance 2>/dev/null | grep -o 'public_ip = "[^"]*"' | cut -d'"' -f2)

# If the above doesn't work, try direct JSON parsing
if [ -z "$VAULT_IP" ]; then
    VAULT_IP=$(terraform output -json vault_instance 2>/dev/null | jq -r '.public_ip')
fi

if [ -z "$VAULT_IP" ] || [ "$VAULT_IP" == "null" ]; then
    echo "Error: Could not retrieve Vault instance IP from Terraform output."
    echo "Make sure 'terraform apply' has been run successfully."
    exit 1
fi

# Get SSH key path from terraform output
SSH_KEY=$(terraform output -raw ssh_private_key_file 2>/dev/null)

if [ -z "$SSH_KEY" ]; then
    # Fall back to default naming convention
    SSH_KEY="ldaplab-key.pem"
fi

if [ ! -f "$SSH_KEY" ]; then
    echo "Error: SSH key file not found: $SSH_KEY"
    exit 1
fi

echo "Vault IP: $VAULT_IP"
echo "SSH Key: $SSH_KEY"
echo ""

# Wait for Vault to be ready
echo "Checking if Vault is ready..."
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ec2-user@"$VAULT_IP" \
        "vault status 2>&1" | grep -q "Initialized"; then
        break
    fi
    echo "Waiting for Vault to be available... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

# Check if Vault is already initialized
INIT_STATUS=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@"$VAULT_IP" \
    "vault status -format=json 2>/dev/null | jq -r '.initialized'" 2>/dev/null || echo "unknown")

if [ "$INIT_STATUS" == "true" ]; then
    echo "Vault is already initialized."
    echo "If you need to reinitialize, you must destroy and recreate the infrastructure."
    exit 0
fi

echo "Initializing Vault..."
echo ""

# Run vault operator init and capture output
# Using 5 recovery key shares with threshold of 3 (default for KMS auto-unseal)
INIT_OUTPUT=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@"$VAULT_IP" \
    "vault operator init" 2>&1)

# Check if init was successful
if echo "$INIT_OUTPUT" | grep -q "Root Token"; then
    echo "Vault initialized successfully!"
    echo ""

    # Save to file with timestamp
    {
        echo "========================================"
        echo "Vault Initialization Output"
        echo "Generated: $(date)"
        echo "Vault Instance: $VAULT_IP"
        echo "========================================"
        echo ""
        echo "$INIT_OUTPUT"
        echo ""
        echo "========================================"
        echo "IMPORTANT: Store these keys securely!"
        echo "The root token is required for initial setup."
        echo "Recovery keys are needed for certain operations"
        echo "when auto-unseal is unavailable."
        echo "========================================"
    } > "$INIT_OUTPUT_FILE"

    # Set restrictive permissions on the keys file
    chmod 600 "$INIT_OUTPUT_FILE"

    echo "Recovery keys and root token saved to: $INIT_OUTPUT_FILE"
    echo ""
    echo "To SSH into the Vault instance:"
    echo "  ssh -i $SSH_KEY ec2-user@$VAULT_IP"
    echo ""
    echo "To use Vault remotely, run:"
    echo "  export VAULT_ADDR=http://$VAULT_IP:8200"
    echo "  export VAULT_TOKEN=<root-token-from-$INIT_OUTPUT_FILE>"
else
    echo "Error: Vault initialization failed."
    echo ""
    echo "Output:"
    echo "$INIT_OUTPUT"
    exit 1
fi
