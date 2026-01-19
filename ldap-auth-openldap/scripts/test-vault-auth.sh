#!/bin/bash
# Test Vault LDAP Authentication
# Usage: ./test-vault-auth.sh
# Requires: VAULT_ADDR environment variable set

set -e

if [ -z "$VAULT_ADDR" ]; then
  echo "ERROR: VAULT_ADDR environment variable is not set"
  echo "Usage: export VAULT_ADDR=http://<vault-nlb>:8200 && ./test-vault-auth.sh"
  exit 1
fi

echo "============================================"
echo "Vault LDAP Authentication Test"
echo "============================================"
echo "VAULT_ADDR: $VAULT_ADDR"
echo ""

# Test 1: Check LDAP auth method is enabled
echo "Test 1: Verify LDAP auth method is enabled"
echo "--------------------------------------------"
vault auth list | grep ldap && echo "LDAP auth is enabled" || echo "LDAP auth NOT found"
echo ""

# Test 2: Read LDAP auth configuration
echo "Test 2: LDAP auth configuration"
echo "--------------------------------------------"
vault read auth/ldap/config 2>/dev/null || echo "Unable to read config (may need privileges)"
echo ""

# Test 3: Login as alice (vault-admins group)
echo "Test 3: Login as alice (vault-admins)"
echo "--------------------------------------------"
echo "Expected: Should receive ldap-admins policy"
ALICE_TOKEN=$(vault login -method=ldap -token-only username=alice password=password123 2>&1) && {
  echo "SUCCESS: alice logged in"
  echo "Token: ${ALICE_TOKEN:0:20}..."

  # Check token details
  VAULT_TOKEN=$ALICE_TOKEN vault token lookup | grep -E "policies|display_name"
} || echo "FAILED: alice login failed"
echo ""

# Test 4: Login as bob (vault-users group)
echo "Test 4: Login as bob (vault-users)"
echo "--------------------------------------------"
echo "Expected: Should receive ldap-users policy"
BOB_TOKEN=$(vault login -method=ldap -token-only username=bob password=password123 2>&1) && {
  echo "SUCCESS: bob logged in"
  echo "Token: ${BOB_TOKEN:0:20}..."

  # Check token details
  VAULT_TOKEN=$BOB_TOKEN vault token lookup | grep -E "policies|display_name"
} || echo "FAILED: bob login failed"
echo ""

# Test 5: Test policy enforcement (alice - admin)
echo "Test 5: Test alice's permissions (ldap-admins)"
echo "--------------------------------------------"
if [ -n "$ALICE_TOKEN" ]; then
  VAULT_TOKEN=$ALICE_TOKEN vault secrets list 2>/dev/null && \
    echo "SUCCESS: alice can list secrets" || \
    echo "alice cannot list secrets (check policy)"
fi
echo ""

# Test 6: Test policy enforcement (bob - user)
echo "Test 6: Test bob's permissions (ldap-users)"
echo "--------------------------------------------"
if [ -n "$BOB_TOKEN" ]; then
  VAULT_TOKEN=$BOB_TOKEN vault secrets list 2>/dev/null && \
    echo "bob can list secrets (unexpected)" || \
    echo "EXPECTED: bob cannot list secrets (read-only policy)"
fi
echo ""

# Test 7: Login with wrong password
echo "Test 7: Login with wrong password (should fail)"
echo "--------------------------------------------"
vault login -method=ldap username=alice password=wrongpassword 2>&1 && \
  echo "ERROR: Should have failed!" || echo "EXPECTED: Login failed (correct behavior)"
echo ""

# Test 8: List LDAP groups configured in Vault
echo "Test 8: List LDAP group mappings in Vault"
echo "--------------------------------------------"
vault list auth/ldap/groups 2>/dev/null || echo "Unable to list groups (may need privileges)"
echo ""

echo "============================================"
echo "Vault LDAP Auth Test Complete!"
echo "============================================"
