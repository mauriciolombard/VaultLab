#!/bin/bash
# Test script for LDAP secrets engine static roles
# Run this on the Vault instance after initialization

set -e

echo "=== LDAP Secrets Engine Static Role Test ==="
echo ""

# Check if VAULT_TOKEN is set
if [ -z "$VAULT_TOKEN" ]; then
    echo "ERROR: VAULT_TOKEN not set. Please export VAULT_TOKEN first."
    exit 1
fi

# Source LDAP environment (if running on Vault instance)
[ -f /etc/profile.d/vault.sh ] && source /etc/profile.d/vault.sh
[ -f /etc/profile.d/ldap.sh ] && source /etc/profile.d/ldap.sh

LDAP_HOST=${LDAP_HOST:-localhost}
LDAP_BASE_DN=${LDAP_BASE_DN:-"dc=vaultlab,dc=local"}
LDAP_BIND_PASS=${LDAP_BIND_PASS:-"admin123"}

echo "Using LDAP_HOST: $LDAP_HOST"
echo "Using LDAP_BASE_DN: $LDAP_BASE_DN"
echo ""

# Ensure LDAP secrets engine is enabled
echo "1. Enabling LDAP secrets engine..."
vault secrets enable ldap || echo "   (already enabled)"

# Configure LDAP secrets engine
echo "2. Configuring LDAP secrets engine..."
vault write ldap/config \
    binddn="cn=admin,$LDAP_BASE_DN" \
    bindpass="$LDAP_BIND_PASS" \
    url="ldap://$LDAP_HOST:389" \
    userdn="ou=services,$LDAP_BASE_DN" \
    userattr="uid" \
    schema="openldap"

# Create a static role for svc-app1
echo "3. Creating static role 'svc-app1-role'..."
vault write ldap/static-role/svc-app1-role \
    dn="uid=svc-app1,ou=services,$LDAP_BASE_DN" \
    username="svc-app1" \
    rotation_period="1h"

# Read static credentials
echo "4. Reading static credentials..."
vault read ldap/static-cred/svc-app1-role

# Test rotation
echo ""
echo "5. Forcing password rotation..."
vault write -f ldap/rotate-role/svc-app1-role

# Read updated credentials
echo ""
echo "6. Reading updated credentials after rotation..."
NEW_CREDS=$(vault read -format=json ldap/static-cred/svc-app1-role)
echo "$NEW_CREDS" | jq .

# Extract password and test LDAP bind
NEW_PASS=$(echo "$NEW_CREDS" | jq -r '.data.password')
echo ""
echo "7. Testing LDAP bind with new password..."
ldapwhoami -x -H ldap://$LDAP_HOST:389 \
    -D "uid=svc-app1,ou=services,$LDAP_BASE_DN" \
    -w "$NEW_PASS" && echo "   SUCCESS: LDAP bind successful!" || echo "   FAILED: LDAP bind failed"

echo ""
echo "=== Static Role Test Complete ==="
