#!/bin/bash
# LDAP troubleshooting script
# Run this on the Vault instance to diagnose LDAP connectivity issues

echo "=== LDAP Troubleshooting Diagnostics ==="
echo "Timestamp: $(date)"
echo ""

# Source environment (if running on Vault instance)
[ -f /etc/profile.d/vault.sh ] && source /etc/profile.d/vault.sh
[ -f /etc/profile.d/ldap.sh ] && source /etc/profile.d/ldap.sh

LDAP_HOST=${LDAP_HOST:-localhost}
LDAP_BASE_DN=${LDAP_BASE_DN:-"dc=vaultlab,dc=local"}
LDAP_BIND_PASS=${LDAP_BIND_PASS:-"admin123"}

echo "=== 1. Environment Variables ==="
echo "LDAP_HOST: $LDAP_HOST"
echo "LDAP_BASE_DN: $LDAP_BASE_DN"
echo "VAULT_ADDR: $VAULT_ADDR"
echo ""

echo "=== 2. Network Connectivity ==="
echo "Testing TCP connection to port 389..."
nc -zv $LDAP_HOST 389 2>&1 || echo "FAILED: Cannot connect to port 389"
echo ""
echo "Testing TCP connection to port 636..."
nc -zv $LDAP_HOST 636 2>&1 || echo "FAILED: Cannot connect to port 636"
echo ""

echo "=== 3. DNS Resolution ==="
nslookup $LDAP_HOST 2>&1 || echo "DNS resolution failed"
echo ""

echo "=== 4. LDAP Anonymous Bind Test ==="
ldapsearch -x -H ldap://$LDAP_HOST:389 -b "" -s base "(objectClass=*)" namingContexts 2>&1
echo ""

echo "=== 5. LDAP Authenticated Bind Test ==="
ldapwhoami -x -H ldap://$LDAP_HOST:389 -D "cn=admin,$LDAP_BASE_DN" -w "$LDAP_BIND_PASS" 2>&1
echo ""

echo "=== 6. LDAP Schema Discovery ==="
echo "Searching for supportedSASLMechanisms..."
ldapsearch -x -H ldap://$LDAP_HOST:389 -b "" -s base "(objectClass=*)" supportedSASLMechanisms 2>&1
echo ""

echo "=== 7. LDAP Base DN Search ==="
ldapsearch -x -H ldap://$LDAP_HOST:389 -D "cn=admin,$LDAP_BASE_DN" -w "$LDAP_BIND_PASS" \
    -b "$LDAP_BASE_DN" -s base "(objectClass=*)" 2>&1
echo ""

echo "=== 8. List Organizational Units ==="
ldapsearch -x -H ldap://$LDAP_HOST:389 -D "cn=admin,$LDAP_BASE_DN" -w "$LDAP_BIND_PASS" \
    -b "$LDAP_BASE_DN" "(objectClass=organizationalUnit)" dn 2>&1
echo ""

echo "=== 9. List Users ==="
ldapsearch -x -H ldap://$LDAP_HOST:389 -D "cn=admin,$LDAP_BASE_DN" -w "$LDAP_BIND_PASS" \
    -b "ou=people,$LDAP_BASE_DN" "(objectClass=inetOrgPerson)" uid cn 2>&1
echo ""

echo "=== 10. Vault LDAP Secrets Engine Status ==="
if [ -n "$VAULT_TOKEN" ]; then
    vault secrets list | grep -q "^ldap/" && {
        echo "LDAP secrets engine is enabled"
        echo ""
        echo "Current configuration:"
        vault read ldap/config
    } || echo "LDAP secrets engine is NOT enabled"
else
    echo "VAULT_TOKEN not set - skipping Vault checks"
fi
echo ""

echo "=== 11. Vault Logs (last 20 lines) ==="
sudo journalctl -u vault --no-pager -n 20 2>&1
echo ""

echo "=== Diagnostics Complete ==="
