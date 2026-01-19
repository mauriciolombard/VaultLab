#!/bin/bash
# Test LDAP connectivity and configuration
# Usage: ./test-ldap.sh <LDAP_SERVER_IP>

set -e

LDAP_SERVER=${1:-$(terraform output -raw ldap_server_public_ip 2>/dev/null || echo "localhost")}
LDAP_PORT=${2:-389}
BASE_DN=${3:-"dc=vaultlab,dc=local"}
ADMIN_DN="cn=admin,$BASE_DN"
ADMIN_PASS=${4:-"admin123"}

echo "============================================"
echo "LDAP Server Test Script"
echo "============================================"
echo "Server: $LDAP_SERVER:$LDAP_PORT"
echo "Base DN: $BASE_DN"
echo ""

# Test 1: Anonymous bind - list base entries
echo "Test 1: Anonymous bind (list base)"
echo "--------------------------------------------"
ldapsearch -x -H ldap://$LDAP_SERVER:$LDAP_PORT -b "$BASE_DN" "(objectClass=*)" dn 2>&1 || echo "Anonymous bind may be disabled"
echo ""

# Test 2: Admin bind - list all entries
echo "Test 2: Admin bind (list all entries)"
echo "--------------------------------------------"
ldapsearch -x -H ldap://$LDAP_SERVER:$LDAP_PORT -b "$BASE_DN" \
  -D "$ADMIN_DN" -w "$ADMIN_PASS" "(objectClass=*)" dn
echo ""

# Test 3: Search for users
echo "Test 3: List all users"
echo "--------------------------------------------"
ldapsearch -x -H ldap://$LDAP_SERVER:$LDAP_PORT -b "ou=users,$BASE_DN" \
  -D "$ADMIN_DN" -w "$ADMIN_PASS" "(objectClass=inetOrgPerson)" uid cn mail
echo ""

# Test 4: Search for groups
echo "Test 4: List all groups"
echo "--------------------------------------------"
ldapsearch -x -H ldap://$LDAP_SERVER:$LDAP_PORT -b "ou=groups,$BASE_DN" \
  -D "$ADMIN_DN" -w "$ADMIN_PASS" "(objectClass=groupOfNames)" cn member
echo ""

# Test 5: Bind as test user (alice)
echo "Test 5: Bind as user 'alice'"
echo "--------------------------------------------"
ldapsearch -x -H ldap://$LDAP_SERVER:$LDAP_PORT -b "$BASE_DN" \
  -D "uid=alice,ou=users,$BASE_DN" -w "password123" "(uid=alice)" dn cn mail && \
  echo "SUCCESS: alice can bind" || echo "FAILED: alice cannot bind"
echo ""

# Test 6: Check group membership for alice
echo "Test 6: Check alice's group membership"
echo "--------------------------------------------"
ldapsearch -x -H ldap://$LDAP_SERVER:$LDAP_PORT -b "ou=groups,$BASE_DN" \
  -D "$ADMIN_DN" -w "$ADMIN_PASS" "(member=uid=alice,ou=users,$BASE_DN)" cn
echo ""

# Test 7: Check group membership for bob
echo "Test 7: Check bob's group membership"
echo "--------------------------------------------"
ldapsearch -x -H ldap://$LDAP_SERVER:$LDAP_PORT -b "ou=groups,$BASE_DN" \
  -D "$ADMIN_DN" -w "$ADMIN_PASS" "(member=uid=bob,ou=users,$BASE_DN)" cn
echo ""

echo "============================================"
echo "LDAP Test Complete!"
echo "============================================"
