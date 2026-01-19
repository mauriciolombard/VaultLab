# LDAP Authentication Troubleshooting Guide

## Quick Diagnostic Commands

### Test LDAP Server Connectivity
```bash
# From Vault node or local machine
nc -zv <LDAP_IP> 389
telnet <LDAP_IP> 389
```

### Test LDAP Bind (Admin)
```bash
ldapsearch -x -H ldap://<LDAP_IP>:389 \
  -D "cn=admin,dc=vaultlab,dc=local" \
  -w "admin123" \
  -b "dc=vaultlab,dc=local" \
  "(objectClass=*)" dn
```

### Test User Bind
```bash
ldapsearch -x -H ldap://<LDAP_IP>:389 \
  -D "uid=alice,ou=users,dc=vaultlab,dc=local" \
  -w "password123" \
  -b "dc=vaultlab,dc=local" \
  "(uid=alice)"
```

### Test Group Membership Query
```bash
ldapsearch -x -H ldap://<LDAP_IP>:389 \
  -D "cn=admin,dc=vaultlab,dc=local" \
  -w "admin123" \
  -b "ou=groups,dc=vaultlab,dc=local" \
  "(member=uid=alice,ou=users,dc=vaultlab,dc=local)" cn
```

## Common Issues and Solutions

### Issue 1: "LDAP connection failed"

**Symptoms:**
```
Error: ldap operation failed: LDAP Result Code 200 "Network Error"
```

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Firewall blocking port 389/636 | Check security groups allow inbound from Vault nodes |
| Wrong LDAP URL | Verify `url` in auth/ldap/config (use private IP if in same VPC) |
| LDAP server not running | SSH to LDAP server, run `systemctl status slapd` |

**Debug:**
```bash
# On Vault node
curl -v ldap://<LDAP_IP>:389

# Check Vault logs
journalctl -u vault -f
```

### Issue 2: "Invalid credentials"

**Symptoms:**
```
Error: ldap operation failed: LDAP Result Code 49 "Invalid Credentials"
```

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Wrong binddn | Verify DN exists: `ldapsearch -x -b "dc=vaultlab,dc=local" "(cn=admin)"` |
| Wrong bindpass | Test bind manually with ldapsearch |
| User DN format wrong | Check userattr and userdn configuration |

**Debug:**
```bash
# Test the exact bind Vault is attempting
ldapsearch -x -H ldap://<LDAP_IP>:389 \
  -D "cn=admin,dc=vaultlab,dc=local" \
  -w "<bindpass>" \
  -b "dc=vaultlab,dc=local"
```

### Issue 3: "User not found"

**Symptoms:**
```
Error: ldap operation failed: user not found
```

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Wrong userdn | Check if users are under the configured OU |
| Wrong userattr | Verify attribute name (uid vs cn vs sAMAccountName) |
| User doesn't exist | Run `ldapsearch -b "ou=users,..." "(objectClass=*)"` |

**Debug:**
```bash
# Search for user manually
ldapsearch -x -H ldap://<LDAP_IP>:389 \
  -D "cn=admin,dc=vaultlab,dc=local" \
  -w "admin123" \
  -b "ou=users,dc=vaultlab,dc=local" \
  "(uid=alice)" dn

# Check all users
ldapsearch -x -H ldap://<LDAP_IP>:389 \
  -D "cn=admin,dc=vaultlab,dc=local" \
  -w "admin123" \
  -b "ou=users,dc=vaultlab,dc=local" \
  "(objectClass=inetOrgPerson)" uid
```

### Issue 4: "No groups found" or wrong policies

**Symptoms:**
- User logs in but doesn't get expected policies
- `vault token lookup` shows only "default" policy

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Wrong groupdn | Verify groups OU path |
| Wrong groupfilter | Test filter manually with ldapsearch |
| Missing group mapping | Run `vault list auth/ldap/groups` |
| Group name mismatch | LDAP group cn must match Vault group name exactly |

**Debug:**
```bash
# Check Vault's group configuration
vault read auth/ldap/config

# List configured group mappings
vault list auth/ldap/groups

# Test group membership query (same filter Vault uses)
ldapsearch -x -H ldap://<LDAP_IP>:389 \
  -D "cn=admin,dc=vaultlab,dc=local" \
  -w "admin123" \
  -b "ou=groups,dc=vaultlab,dc=local" \
  "(member=uid=alice,ou=users,dc=vaultlab,dc=local)" cn
```

### Issue 5: TLS/SSL Issues

**Symptoms:**
```
Error: LDAP Result Code 200 "Network Error": x509: certificate signed by unknown authority
```

**Solutions:**

| Scenario | Configuration |
|----------|---------------|
| No TLS (testing only) | Set `starttls=false`, use port 389 |
| Self-signed cert | Set `insecure_tls=true` |
| Valid cert | Configure `certificate` parameter with CA cert |

## Vault LDAP Debug Logging

Enable debug logging on Vault to see LDAP operations:

```bash
# In vault config.hcl
log_level = "debug"

# Or via environment
export VAULT_LOG_LEVEL=debug
```

Then watch logs:
```bash
journalctl -u vault -f | grep -i ldap
```

## LDAP Server Diagnostics

### Check OpenLDAP Service
```bash
# On LDAP server
systemctl status slapd
journalctl -u slapd -f
```

### Check LDAP Database
```bash
# List all entries
ldapsearch -x -H ldap://localhost:389 \
  -D "cn=admin,dc=vaultlab,dc=local" \
  -w "admin123" \
  -b "dc=vaultlab,dc=local" \
  "(objectClass=*)" dn
```

### Verify Schema
```bash
# Check if required object classes are loaded
ldapsearch -x -H ldap://localhost:389 -b "cn=schema,cn=config" \
  "(objectClass=*)" | grep -i inetorgperson
```

## Configuration Validation Checklist

```
[ ] LDAP server is reachable from Vault (port 389/636 open)
[ ] binddn exists and can authenticate
[ ] binddn has read permissions on userdn and groupdn
[ ] Users exist under userdn with correct userattr
[ ] Groups exist under groupdn with member attribute
[ ] groupfilter syntax matches your LDAP schema
[ ] Vault group mappings match LDAP group names (case-sensitive)
[ ] Policies exist and are attached to Vault groups
```

## Quick Reset Procedure

If LDAP auth is misconfigured and you need to start fresh:

```bash
# Disable and re-enable LDAP auth
vault auth disable ldap
vault auth enable ldap

# Reconfigure from scratch
vault write auth/ldap/config \
    url="ldap://<LDAP_IP>:389" \
    binddn="cn=admin,dc=vaultlab,dc=local" \
    bindpass="admin123" \
    userdn="ou=users,dc=vaultlab,dc=local" \
    userattr="uid" \
    groupdn="ou=groups,dc=vaultlab,dc=local" \
    groupattr="cn" \
    groupfilter="(member={{.UserDN}})"

# Recreate group mappings
vault write auth/ldap/groups/vault-admins policies="ldap-admins"
vault write auth/ldap/groups/vault-users policies="ldap-users"
```
