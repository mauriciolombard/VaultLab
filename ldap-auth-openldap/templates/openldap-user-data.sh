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

echo "Installing OpenLDAP on Amazon Linux 2023..."
echo "Domain: $LDAP_DOMAIN"
echo "Base DN: $BASE_DN"

# Update system
dnf update -y

# Install OpenLDAP server and utilities
dnf install -y openldap openldap-servers openldap-clients

# Start slapd service
systemctl start slapd
systemctl enable slapd

# Generate password hash
ADMIN_PASS_HASH=$(slappasswd -s "$LDAP_ADMIN_PASSWORD")

# Configure the root password
cat > /tmp/chrootpw.ldif << EOF
dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $ADMIN_PASS_HASH
EOF

ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/chrootpw.ldif

# Import basic schemas
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif

# Find the correct MDB database number (varies by distro/version)
MDB_DB=$(ldapsearch -Y EXTERNAL -H ldapi:/// -b 'cn=config' '(olcDatabase=*)' dn 2>/dev/null | grep 'olcDatabase=.*mdb' | sed 's/dn: //' | head -1)
if [ -z "$MDB_DB" ]; then
  echo "ERROR: Could not find MDB database in cn=config"
  exit 1
fi
echo "Found MDB database: $MDB_DB"

# Configure database
cat > /tmp/chdomain.ldif << EOF
dn: $MDB_DB
changetype: modify
replace: olcSuffix
olcSuffix: $BASE_DN

dn: $MDB_DB
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,$BASE_DN

dn: $MDB_DB
changetype: modify
add: olcRootPW
olcRootPW: $ADMIN_PASS_HASH

dn: $MDB_DB
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by dn="cn=admin,$BASE_DN" write by anonymous auth by self write by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by dn="cn=admin,$BASE_DN" write by * read
EOF

ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/chdomain.ldif

# Create base structure
cat > /tmp/basedomain.ldif << EOF
dn: $BASE_DN
objectClass: top
objectClass: dcObject
objectClass: organization
o: VaultLab
dc: $${DOMAIN_PARTS[0]}

dn: cn=admin,$BASE_DN
objectClass: organizationalRole
cn: admin
description: LDAP Administrator

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
