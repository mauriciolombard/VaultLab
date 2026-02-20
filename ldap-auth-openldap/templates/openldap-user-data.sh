#!/bin/bash
set -e

# Variables from Terraform
LDAP_DOMAIN="${ldap_domain}"
LDAP_ADMIN_PASSWORD="${ldap_admin_password}"
LDAP_TEST_USER_PASSWORD="${ldap_test_user_password}"

# Convert domain to base DN (e.g., vaultlab.local -> dc=vaultlab,dc=local)
IFS='.' read -ra DOMAIN_PARTS <<< "$LDAP_DOMAIN"
BASE_DN=""
for part in "$${DOMAIN_PARTS[@]}"; do
  if [ -n "$BASE_DN" ]; then
    BASE_DN="$BASE_DN,dc=$part"
  else
    BASE_DN="dc=$part"
  fi
done

echo "Installing OpenLDAP on Ubuntu 24.04..."
echo "Domain: $LDAP_DOMAIN"
echo "Base DN: $BASE_DN"

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# Pre-seed slapd configuration to avoid interactive prompts
debconf-set-selections <<EOF
slapd slapd/internal/generated_adminpw password $LDAP_ADMIN_PASSWORD
slapd slapd/internal/adminpw password $LDAP_ADMIN_PASSWORD
slapd slapd/password1 password $LDAP_ADMIN_PASSWORD
slapd slapd/password2 password $LDAP_ADMIN_PASSWORD
slapd slapd/domain string $LDAP_DOMAIN
slapd shared/organization string VaultLab
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/no_configuration boolean false
EOF

# Install OpenLDAP server and utilities
apt-get install -y slapd ldap-utils

# Reconfigure slapd with our domain settings
dpkg-reconfigure -f noninteractive slapd

# Generate password hash
ADMIN_PASS_HASH=$(slappasswd -s "$LDAP_ADMIN_PASSWORD")

# Import additional schemas (cosine and inetorgperson are loaded by default on Ubuntu;
# nis needs to be added)
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/ldap/schema/nis.ldif 2>/dev/null || true

# Create base structure (OU for users and groups)
cat > /tmp/basedomain.ldif << EOF
dn: ou=users,$BASE_DN
objectClass: organizationalUnit
ou: users

dn: ou=groups,$BASE_DN
objectClass: organizationalUnit
ou: groups
EOF

ldapadd -x -D "cn=admin,$BASE_DN" -w "$LDAP_ADMIN_PASSWORD" -f /tmp/basedomain.ldif

# Create test users
cat > /tmp/users.ldif << EOF
# User: alice (member of vault-admins)
dn: uid=alice,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Alice Admin
sn: Admin
uid: alice
uidNumber: 1001
gidNumber: 1001
homeDirectory: /home/alice
loginShell: /bin/bash
userPassword: $(slappasswd -s "$LDAP_TEST_USER_PASSWORD")
mail: alice@$LDAP_DOMAIN

# User: bob (member of vault-users)
dn: uid=bob,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Bob User
sn: User
uid: bob
uidNumber: 1002
gidNumber: 1002
homeDirectory: /home/bob
loginShell: /bin/bash
userPassword: $(slappasswd -s "$LDAP_TEST_USER_PASSWORD")
mail: bob@$LDAP_DOMAIN

# User: charlie (member of vault-users)
dn: uid=charlie,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Charlie User
sn: User
uid: charlie
uidNumber: 1003
gidNumber: 1003
homeDirectory: /home/charlie
loginShell: /bin/bash
userPassword: $(slappasswd -s "$LDAP_TEST_USER_PASSWORD")
mail: charlie@$LDAP_DOMAIN
EOF

ldapadd -x -D "cn=admin,$BASE_DN" -w "$LDAP_ADMIN_PASSWORD" -f /tmp/users.ldif

# Create groups
cat > /tmp/groups.ldif << EOF
# Group: vault-admins
dn: cn=vault-admins,ou=groups,$BASE_DN
objectClass: groupOfNames
cn: vault-admins
description: Vault Administrators
member: uid=alice,ou=users,$BASE_DN

# Group: vault-users
dn: cn=vault-users,ou=groups,$BASE_DN
objectClass: groupOfNames
cn: vault-users
description: Vault Users
member: uid=bob,ou=users,$BASE_DN
member: uid=charlie,ou=users,$BASE_DN
EOF

ldapadd -x -D "cn=admin,$BASE_DN" -w "$LDAP_ADMIN_PASSWORD" -f /tmp/groups.ldif

# Clean up temporary files
rm -f /tmp/*.ldif

# Verify installation
echo "OpenLDAP installation complete. Verifying..."
ldapsearch -x -H ldap://localhost:389 -b "$BASE_DN" "(objectClass=*)" dn

echo "OpenLDAP server is ready!"
echo "Base DN: $BASE_DN"
echo "Admin DN: cn=admin,$BASE_DN"
echo "Test users: alice, bob, charlie"
