#!/bin/bash
# Test script for LDAP secrets engine dynamic credentials
# Run this on the Vault instance after initialization

set -e

echo "=== LDAP Secrets Engine Dynamic Role Test ==="
echo ""

# Check if VAULT_TOKEN is set
if [ -z "$VAULT_TOKEN" ]; then
    echo "ERROR: VAULT_TOKEN not set. Please export VAULT_TOKEN first."
    exit 1
fi

# Source environment (if running on Vault instance)
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
    schema="openldap"

# Create a dynamic role
echo "3. Creating dynamic role 'dynamic-user'..."
vault write ldap/role/dynamic-user \
    creation_ldif="$(cat <<EOF
dn: uid={{.Username}},ou=people,$LDAP_BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: {{.Username}}
cn: {{.Username}}
sn: Dynamic
givenName: User
displayName: Dynamic User {{.Username}}
uidNumber: {{.UID}}
gidNumber: 5001
userPassword: {{.Password}}
homeDirectory: /home/{{.Username}}
loginShell: /bin/bash
EOF
)" \
    deletion_ldif="$(cat <<EOF
dn: uid={{.Username}},ou=people,$LDAP_BASE_DN
changetype: delete
EOF
)" \
    rollback_ldif="$(cat <<EOF
dn: uid={{.Username}},ou=people,$LDAP_BASE_DN
changetype: delete
EOF
)" \
    default_ttl="1h" \
    max_ttl="24h"

# Generate dynamic credentials
echo "4. Generating dynamic credentials..."
CREDS=$(vault read -format=json ldap/creds/dynamic-user)
echo "$CREDS" | jq .

USERNAME=$(echo "$CREDS" | jq -r '.data.username')
PASSWORD=$(echo "$CREDS" | jq -r '.data.password')
LEASE_ID=$(echo "$CREDS" | jq -r '.lease_id')

echo ""
echo "5. Testing LDAP bind with dynamic credentials..."
ldapwhoami -x -H ldap://$LDAP_HOST:389 \
    -D "uid=$USERNAME,ou=people,$LDAP_BASE_DN" \
    -w "$PASSWORD" && echo "   SUCCESS: LDAP bind successful!" || echo "   FAILED: LDAP bind failed"

echo ""
echo "6. Verifying user exists in LDAP..."
ldapsearch -x -H ldap://$LDAP_HOST:389 \
    -D "cn=admin,$LDAP_BASE_DN" \
    -w "$LDAP_BIND_PASS" \
    -b "ou=people,$LDAP_BASE_DN" \
    "(uid=$USERNAME)" dn cn

echo ""
echo "7. Revoking lease to delete user..."
vault lease revoke "$LEASE_ID"

echo ""
echo "8. Verifying user was deleted..."
sleep 2
ldapsearch -x -H ldap://$LDAP_HOST:389 \
    -D "cn=admin,$LDAP_BASE_DN" \
    -w "$LDAP_BIND_PASS" \
    -b "ou=people,$LDAP_BASE_DN" \
    "(uid=$USERNAME)" dn 2>&1 | grep -q "numEntries: 0" && echo "   SUCCESS: User deleted!" || echo "   User still exists or search failed"

echo ""
echo "=== Dynamic Role Test Complete ==="
