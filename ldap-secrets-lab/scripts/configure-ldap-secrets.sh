#!/bin/bash
# Helper script to configure Vault LDAP secrets engine
# Run after Vault is initialized and unsealed
#
# Prerequisites:
#   - VAULT_TOKEN must be set (root token or token with appropriate permissions)
#   - VAULT_ADDR should be set (defaults to http://127.0.0.1:8200)
#   - LDAP_HOST and LDAP_BASE_DN are auto-set via /etc/profile.d/vault.sh

set -e

# Source environment if not already set
if [[ -z "$LDAP_HOST" || -z "$LDAP_BASE_DN" ]]; then
    if [[ -f /etc/profile.d/vault.sh ]]; then
        source /etc/profile.d/vault.sh
    fi
fi

# Validate required variables
LDAP_HOST="${LDAP_HOST:?LDAP_HOST environment variable is required}"
LDAP_BASE_DN="${LDAP_BASE_DN:?LDAP_BASE_DN environment variable is required}"
LDAP_BIND_DN="cn=admin,$LDAP_BASE_DN"
LDAP_BIND_PASS="${LDAP_BIND_PASS:-admin123}"

# Check if VAULT_TOKEN is set
if [[ -z "$VAULT_TOKEN" ]]; then
    echo "ERROR: VAULT_TOKEN is not set"
    echo "Please set your Vault token: export VAULT_TOKEN=<your-root-token>"
    exit 1
fi

echo "=== Configuring Vault LDAP Secrets Engine ==="
echo "LDAP Host: $LDAP_HOST"
echo "LDAP Base DN: $LDAP_BASE_DN"
echo "LDAP Bind DN: $LDAP_BIND_DN"
echo ""

echo "Enabling LDAP secrets engine..."
vault secrets enable ldap 2>/dev/null || echo "  (already enabled)"

echo "Configuring LDAP secrets engine..."
vault write ldap/config \
    binddn="$LDAP_BIND_DN" \
    bindpass="$LDAP_BIND_PASS" \
    url="ldap://$LDAP_HOST:389" \
    userdn="ou=people,$LDAP_BASE_DN" \
    userattr="uid" \
    schema="openldap"

echo ""
echo "=== LDAP secrets engine configured! ==="
echo ""
echo "Next steps:"
echo "  - Test connection: vault read ldap/config"
echo "  - Create static roles: ./scripts/test-static-role.sh"
echo "  - Create dynamic roles: ./scripts/test-dynamic-role.sh"
echo "  - Test library sets: ./scripts/test-library-set.sh"
