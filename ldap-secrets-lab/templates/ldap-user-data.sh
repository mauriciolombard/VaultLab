#!/bin/bash
set -ex

# Variables from Terraform
LDAP_DOMAIN="${ldap_domain}"
LDAP_ORGANISATION="${ldap_organisation}"
LDAP_ADMIN_PASS="${ldap_admin_pass}"
ENABLE_TLS="${enable_tls}"
LDAP_BASE_DN="${ldap_base_dn}"

# Get instance metadata
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

# Install Docker
dnf install -y docker jq tcpdump openldap-clients
systemctl enable docker
systemctl start docker

# Create directories for LDAP data and config
mkdir -p /opt/ldap/data /opt/ldap/config /opt/ldap/seed /opt/ldap/certs

# Generate self-signed certificates for LDAPS
if [ "$${ENABLE_TLS}" = "true" ]; then
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /opt/ldap/certs/ldap.key \
    -out /opt/ldap/certs/ldap.crt \
    -subj "/C=US/ST=CA/L=SanFrancisco/O=$${LDAP_ORGANISATION}/CN=$${PRIVATE_IP}"
  chmod 644 /opt/ldap/certs/*
fi

# Create LDIF seed file with test users and groups
cat > /opt/ldap/seed/seed.ldif <<EOF
# Create organizational units
dn: ou=people,$${LDAP_BASE_DN}
objectClass: organizationalUnit
ou: people

dn: ou=groups,$${LDAP_BASE_DN}
objectClass: organizationalUnit
ou: groups

dn: ou=services,$${LDAP_BASE_DN}
objectClass: organizationalUnit
ou: services

# Create test users
dn: uid=alice,ou=people,$${LDAP_BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: alice
sn: Smith
givenName: Alice
cn: Alice Smith
displayName: Alice Smith
uidNumber: 10001
gidNumber: 5001
userPassword: alice123
homeDirectory: /home/alice
loginShell: /bin/bash
mail: alice@$${LDAP_DOMAIN}

dn: uid=bob,ou=people,$${LDAP_BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: bob
sn: Jones
givenName: Bob
cn: Bob Jones
displayName: Bob Jones
uidNumber: 10002
gidNumber: 5001
userPassword: bob123
homeDirectory: /home/bob
loginShell: /bin/bash
mail: bob@$${LDAP_DOMAIN}

dn: uid=charlie,ou=people,$${LDAP_BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: charlie
sn: Brown
givenName: Charlie
cn: Charlie Brown
displayName: Charlie Brown
uidNumber: 10003
gidNumber: 5001
userPassword: charlie123
homeDirectory: /home/charlie
loginShell: /bin/bash
mail: charlie@$${LDAP_DOMAIN}

# Create service accounts (for static role testing)
dn: uid=svc-app1,ou=services,$${LDAP_BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: svc-app1
sn: Service
givenName: App1
cn: App1 Service Account
displayName: App1 Service Account
uidNumber: 20001
gidNumber: 5002
userPassword: svc-app1-pass
homeDirectory: /home/svc-app1
loginShell: /bin/false

dn: uid=svc-app2,ou=services,$${LDAP_BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: svc-app2
sn: Service
givenName: App2
cn: App2 Service Account
displayName: App2 Service Account
uidNumber: 20002
gidNumber: 5002
userPassword: svc-app2-pass
homeDirectory: /home/svc-app2
loginShell: /bin/false

# Create groups
dn: cn=developers,ou=groups,$${LDAP_BASE_DN}
objectClass: posixGroup
cn: developers
gidNumber: 5001
memberUid: alice
memberUid: bob

dn: cn=admins,ou=groups,$${LDAP_BASE_DN}
objectClass: posixGroup
cn: admins
gidNumber: 5002
memberUid: charlie

dn: cn=service-accounts,ou=groups,$${LDAP_BASE_DN}
objectClass: posixGroup
cn: service-accounts
gidNumber: 5003
memberUid: svc-app1
memberUid: svc-app2

# User with special characters in DN (edge case testing)
dn: uid=user.with" special,ou=people,$${LDAP_BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: user.with" special
sn: Special
givenName: User
cn: User Special
displayName: User with Special Characters
uidNumber: 10099
gidNumber: 5001
userPassword: special123
homeDirectory: /home/special
loginShell: /bin/bash

# Nested group example
dn: cn=all-users,ou=groups,$${LDAP_BASE_DN}
objectClass: posixGroup
cn: all-users
gidNumber: 5000
memberUid: alice
memberUid: bob
memberUid: charlie
EOF

# Set TLS environment variable for Docker
if [ "$${ENABLE_TLS}" = "true" ]; then
  LDAP_TLS_VERIFY="try"
else
  LDAP_TLS_VERIFY="never"
fi

# Run OpenLDAP container
docker run -d \
  --name openldap \
  --restart unless-stopped \
  -p 389:389 \
  -p 636:636 \
  -e LDAP_ORGANISATION="$${LDAP_ORGANISATION}" \
  -e LDAP_DOMAIN="$${LDAP_DOMAIN}" \
  -e LDAP_ADMIN_PASSWORD="$${LDAP_ADMIN_PASS}" \
  -e LDAP_CONFIG_PASSWORD="$${LDAP_ADMIN_PASS}" \
  -e LDAP_TLS_VERIFY_CLIENT="$${LDAP_TLS_VERIFY}" \
  -e LDAP_LOG_LEVEL=256 \
  -v /opt/ldap/data:/var/lib/ldap \
  -v /opt/ldap/config:/etc/ldap/slapd.d \
  -v /opt/ldap/seed:/container/service/slapd/assets/config/bootstrap/ldif/custom \
  osixia/openldap:1.5.0 \
  --copy-service --loglevel debug

# Wait for OpenLDAP to start
sleep 15

# Run phpLDAPadmin container
docker run -d \
  --name phpldapadmin \
  --restart unless-stopped \
  -p 8080:80 \
  -e PHPLDAPADMIN_LDAP_HOSTS="$${PRIVATE_IP}" \
  -e PHPLDAPADMIN_HTTPS=false \
  osixia/phpldapadmin:0.9.0

# Create helper scripts
cat > /home/ec2-user/ldap-status.sh <<'SCRIPT'
#!/bin/bash
echo "=== OpenLDAP Container Status ==="
docker ps -a | grep -E "openldap|phpldapadmin"
echo ""
echo "=== OpenLDAP Logs (last 20 lines) ==="
docker logs --tail 20 openldap
echo ""
echo "=== Test LDAP Connection ==="
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,$LDAP_BASE_DN" -w "$LDAP_ADMIN_PASS" -b "$LDAP_BASE_DN" "(objectClass=organizationalUnit)" dn 2>/dev/null || echo "LDAP connection test failed"
SCRIPT
chmod +x /home/ec2-user/ldap-status.sh

cat > /home/ec2-user/ldap-search.sh <<'SCRIPT'
#!/bin/bash
# Usage: ./ldap-search.sh [filter] [attributes]
FILTER=$${1:-"(objectClass=*)"}
ATTRS=$${2:-"dn"}
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,$LDAP_BASE_DN" -w "$LDAP_ADMIN_PASS" -b "$LDAP_BASE_DN" "$FILTER" $ATTRS
SCRIPT
chmod +x /home/ec2-user/ldap-search.sh

cat > /home/ec2-user/ldap-add-user.sh <<'SCRIPT'
#!/bin/bash
# Usage: ./ldap-add-user.sh <username> <password> <firstname> <lastname>
if [ $# -lt 4 ]; then
  echo "Usage: $0 <username> <password> <firstname> <lastname>"
  exit 1
fi
USERNAME=$1
PASSWORD=$2
FIRSTNAME=$3
LASTNAME=$4
UID_NUM=$((10100 + RANDOM % 1000))

cat <<EOF | ldapadd -x -H ldap://localhost:389 -D "cn=admin,$LDAP_BASE_DN" -w "$LDAP_ADMIN_PASS"
dn: uid=$USERNAME,ou=people,$LDAP_BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: $USERNAME
sn: $LASTNAME
givenName: $FIRSTNAME
cn: $FIRSTNAME $LASTNAME
displayName: $FIRSTNAME $LASTNAME
uidNumber: $UID_NUM
gidNumber: 5001
userPassword: $PASSWORD
homeDirectory: /home/$USERNAME
loginShell: /bin/bash
EOF
SCRIPT
chmod +x /home/ec2-user/ldap-add-user.sh

cat > /home/ec2-user/toggle-tls.sh <<'SCRIPT'
#!/bin/bash
# Toggle TLS mode for OpenLDAP
echo "Current LDAP container config:"
docker inspect openldap | jq '.[0].Config.Env' | grep -i tls
echo ""
echo "To enable/disable TLS, you need to recreate the container."
echo "Edit /opt/ldap/docker-compose.yml and run: docker-compose up -d"
SCRIPT
chmod +x /home/ec2-user/toggle-tls.sh

# Set environment variables for all users
cat > /etc/profile.d/ldap.sh <<EOF
export LDAP_BASE_DN="$${LDAP_BASE_DN}"
export LDAP_ADMIN_PASS="$${LDAP_ADMIN_PASS}"
export LDAP_HOST="$${PRIVATE_IP}"
EOF

chown ec2-user:ec2-user /home/ec2-user/*.sh

echo "OpenLDAP setup complete!"
echo "phpLDAPadmin available at: http://$${PRIVATE_IP}:8080"
echo "Login DN: cn=admin,$${LDAP_BASE_DN}"
echo "Password: $${LDAP_ADMIN_PASS}"
