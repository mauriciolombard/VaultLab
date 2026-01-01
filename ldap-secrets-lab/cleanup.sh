#!/bin/bash
# Cleanup script to remove Terraform-generated files
# Run this before sharing the repository or after terraform destroy

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Cleaning up ldap-secrets-lab..."

# Remove Terraform state files
rm -f terraform.tfstate terraform.tfstate.backup

# Remove Terraform plan files
rm -f *.tfplan

# Remove Terraform lock file
rm -f .terraform.lock.hcl

# Remove Terraform providers directory
rm -rf .terraform/

# Remove Vault init keys
rm -f vault-init-keys.json

# Remove packet captures
rm -f *.pcap

echo "Cleanup complete!"
echo ""
echo "Files removed:"
echo "  - terraform.tfstate*"
echo "  - .terraform/"
echo "  - .terraform.lock.hcl"
echo "  - *.pem"
echo "  - vault-init-keys.json"
echo "  - *.pcap"
