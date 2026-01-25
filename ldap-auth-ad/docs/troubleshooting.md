# Active Directory LDAP Authentication Troubleshooting Guide

## Quick Diagnostic Commands

> **Note:** All `ldapsearch` commands in this guide must be run from **inside the VPC** (e.g., SSH into a Vault node). The AD server's LDAP port 389 is not exposed to the internet for security reasons. See the README for SSH instructions.

### Test AD Server Connectivity
```bash
# From Vault node or local machine
nc -zv <AD_IP> 389
nc -zv <AD_IP> 636
telnet <AD_IP> 389
```

### Test RootDSE (Anonymous Query)
```bash
ldapsearch -x -H ldap://<AD_IP>:389 -b "" -s base "(objectClass=*)" \
    defaultNamingContext dnsHostName
```

### Test Service Account Bind
```bash
# Using UPN format (preferred)
ldapsearch -x -H ldap://<AD_IP>:389 \
    -D "vault-svc@vaultlab.local" \
    -w "VaultBind123!" \
    -b "DC=vaultlab,DC=local" \
    "(objectClass=top)" dn
```

### Test User Bind
```bash
ldapsearch -x -H ldap://<AD_IP>:389 \
    -D "alice@vaultlab.local" \
    -w "Password123!" \
    -b "DC=vaultlab,DC=local" \
    "(sAMAccountName=alice)"
```

## Common Issues and Solutions

### Issue 1: AD Server Not Ready

**Symptoms:**
- Cannot connect to LDAP port 389
- Connection refused or timeout

**Cause:** Windows AD setup takes 10-15 minutes after EC2 launch.

**Solution:**
1. Wait for AD DS installation to complete
2. Check setup log via RDP: `C:\AD-Setup.log`
3. Verify AD is operational:
```powershell
# On Windows server via RDP
Get-ADDomain
Get-ADUser -Filter * | Select-Object SamAccountName
```

### Issue 2: "LDAP connection failed"

**Symptoms:**
```
Error: ldap operation failed: LDAP Result Code 200 "Network Error"
```

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Firewall blocking ports | Check security groups allow 389, 636 from Vault |
| Wrong LDAP URL | Use private IP if in same VPC |
| AD not ready | Wait 10-15 min, check C:\AD-Setup.log |

**Debug:**
```bash
# Test connectivity
nc -zv <AD_IP> 389
curl -v ldap://<AD_IP>:389
```

### Issue 3: "Invalid credentials" for Service Account

**Symptoms:**
```
Error: ldap operation failed: LDAP Result Code 49 "Invalid Credentials"
```

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Wrong password | Verify service account password |
| Wrong bind format | Use UPN: `vault-svc@vaultlab.local` |
| Account disabled | Check account status in AD |
| Account locked | Check for lockout in AD |

**Debug - Test bind formats:**
```bash
# UPN format (recommended for AD)
ldapsearch -x -H ldap://<AD_IP>:389 \
    -D "vault-svc@vaultlab.local" \
    -w "VaultBind123!" \
    -b "" -s base

# DN format (alternative)
ldapsearch -x -H ldap://<AD_IP>:389 \
    -D "CN=vault-svc,CN=Users,DC=vaultlab,DC=local" \
    -w "VaultBind123!" \
    -b "" -s base

# DOMAIN\user format
ldapsearch -x -H ldap://<AD_IP>:389 \
    -D "VAULTLAB\\vault-svc" \
    -w "VaultBind123!" \
    -b "" -s base
```

### Issue 4: "User not found"

**Symptoms:**
```
Error: ldap operation failed: user "alice" not found
```

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Wrong userattr | Must be `sAMAccountName` for AD (not `uid`) |
| Wrong userdn | Check user is in `CN=Users,DC=...` |
| User doesn't exist | Verify user in AD |
| User in different OU | Update userdn to include correct OU |

**Debug:**
```bash
# Check current Vault config
vault read auth/ldap/config | grep -E "userdn|userattr"

# Search for user in AD
ldapsearch -x -H ldap://<AD_IP>:389 \
    -D "vault-svc@vaultlab.local" \
    -w "VaultBind123!" \
    -b "CN=Users,DC=vaultlab,DC=local" \
    "(sAMAccountName=alice)" dn sAMAccountName

# List all users
ldapsearch -x -H ldap://<AD_IP>:389 \
    -D "vault-svc@vaultlab.local" \
    -w "VaultBind123!" \
    -b "CN=Users,DC=vaultlab,DC=local" \
    "(objectClass=user)" sAMAccountName
```

### Issue 5: "User authenticates but no groups/wrong policies"

**Symptoms:**
- Login succeeds but token only has "default" policy
- Expected policies not attached

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Group name case mismatch | AD group names are case-sensitive in Vault |
| Wrong groupdn | Verify groups are in configured container |
| Wrong groupfilter | Use AD-specific filter with OID |
| Missing group mapping | Create Vault group config |

**Debug:**
```bash
# Check Vault group mappings
vault list auth/ldap/groups

# Verify group name matches EXACTLY (case-sensitive!)
vault read auth/ldap/groups/Vault-Admins

# Search for user's groups in AD
ldapsearch -x -H ldap://<AD_IP>:389 \
    -D "vault-svc@vaultlab.local" \
    -w "VaultBind123!" \
    -b "CN=Users,DC=vaultlab,DC=local" \
    "(sAMAccountName=alice)" memberOf

# Test Vault's group filter directly
ALICE_DN="CN=Alice Admin,CN=Users,DC=vaultlab,DC=local"
ldapsearch -x -H ldap://<AD_IP>:389 \
    -D "vault-svc@vaultlab.local" \
    -w "VaultBind123!" \
    -b "CN=Users,DC=vaultlab,DC=local" \
    "(&(objectClass=group)(member:1.2.840.113556.1.4.1941:=$ALICE_DN))" cn
```

### Issue 6: Group Name Case Sensitivity

**CRITICAL:** Vault group names MUST match AD group names exactly!

```bash
# WRONG - lowercase won't match "Vault-Admins"
vault write auth/ldap/groups/vault-admins policies="ldap-admins"

# CORRECT - matches AD group name
vault write auth/ldap/groups/Vault-Admins policies="ldap-admins"
```

**Check AD group name:**
```bash
ldapsearch -x -H ldap://<AD_IP>:389 \
    -D "vault-svc@vaultlab.local" \
    -w "VaultBind123!" \
    -b "CN=Users,DC=vaultlab,DC=local" \
    "(objectClass=group)" cn | grep -i vault
```

### Issue 7: UPN Login Not Working

**Symptoms:**
- `vault login -method=ldap username=alice@vaultlab.local` fails
- Regular username login works

**Solution:**
```bash
# Ensure upndomain is configured
vault read auth/ldap/config | grep upndomain

# If missing, reconfigure:
vault write auth/ldap/config \
    ... \
    upndomain="vaultlab.local"
```

## AD Server Diagnostics (via RDP)

### Check AD DS Service Status
```powershell
Get-Service NTDS
Get-Service DNS
```

### Check AD Setup Log
```powershell
Get-Content C:\AD-Setup.log
```

### Verify AD is Operational
```powershell
Get-ADDomain
Get-ADForest
```

### List Users and Groups
```powershell
Get-ADUser -Filter * | Select-Object SamAccountName, Enabled
Get-ADGroup -Filter 'Name -like "Vault*"' | Select-Object Name
Get-ADGroupMember -Identity "Vault-Admins" | Select-Object SamAccountName
```

### Check Service Account
```powershell
Get-ADUser -Identity "vault-svc" -Properties *
```

### Test LDAP Locally on AD Server
```powershell
# Install RSAT LDAP tools if needed
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0

# Test query
dsquery user -name alice
dsquery group -name "Vault*"
```

## Vault Debug Logging

Enable debug logging to see LDAP operations:

```bash
# Set log level in vault config
log_level = "debug"

# Or via environment
export VAULT_LOG_LEVEL=debug

# Watch logs
journalctl -u vault -f | grep -i ldap
```

## Configuration Validation Checklist

```
[ ] AD server is reachable from Vault (port 389 open)
[ ] Service account (vault-svc) exists and can bind
[ ] userattr = sAMAccountName (not uid)
[ ] userdn points to correct container (CN=Users,DC=...)
[ ] Test users exist (alice, bob, charlie)
[ ] Security groups exist (Vault-Admins, Vault-Users)
[ ] Users are members of correct groups
[ ] groupfilter uses AD OID (1.2.840.113556.1.4.1941)
[ ] Vault group mappings exist with EXACT case match
[ ] Policies exist and are attached to groups
```

## Quick Reset Procedure

If LDAP auth is misconfigured:

```bash
# Disable and re-enable
vault auth disable ldap
vault auth enable ldap

# Reconfigure for AD
vault write auth/ldap/config \
    url="ldap://<AD_IP>:389" \
    binddn="vault-svc@vaultlab.local" \
    bindpass="VaultBind123!" \
    userdn="CN=Users,DC=vaultlab,DC=local" \
    userattr="sAMAccountName" \
    upndomain="vaultlab.local" \
    groupdn="CN=Users,DC=vaultlab,DC=local" \
    groupattr="cn" \
    groupfilter="(&(objectClass=group)(member:1.2.840.113556.1.4.1941:={{.UserDN}}))"

# Recreate group mappings (CASE-SENSITIVE!)
vault write auth/ldap/groups/Vault-Admins policies="ldap-admins"
vault write auth/ldap/groups/Vault-Users policies="ldap-users"
```

## Windows Firewall (if enabled)

If Windows Firewall is blocking LDAP:

```powershell
# Allow LDAP (389)
New-NetFirewallRule -DisplayName "LDAP" -Direction Inbound -Protocol TCP -LocalPort 389 -Action Allow

# Allow LDAPS (636)
New-NetFirewallRule -DisplayName "LDAPS" -Direction Inbound -Protocol TCP -LocalPort 636 -Action Allow

# Allow Global Catalog
New-NetFirewallRule -DisplayName "GC" -Direction Inbound -Protocol TCP -LocalPort 3268 -Action Allow
```
