# Vault LDAP Authentication Configuration for Active Directory

locals {
  ad_base_dn = "DC=${replace(var.ad_domain_name, ".", ",DC=")}"
}

# Configure LDAP auth method for Active Directory
# Note: vault_ldap_auth_backend enables the auth backend automatically
resource "vault_ldap_auth_backend" "ad" {
  count = var.configure_vault_ldap ? 1 : 0

  path         = "ldap"
  description  = "LDAP authentication for Active Directory"
  url          = "ldap://${aws_instance.windows_ad.private_ip}:389"
  starttls     = false
  insecure_tls = true

  # Bind credentials (service account for LDAP searches)
  # Using UPN format for AD: user@domain
  binddn   = "vault-svc@${var.ad_domain_name}"
  bindpass = var.ad_admin_password

  # User search configuration for AD
  # AD stores users in CN=Users container by default
  userdn   = "CN=Users,${local.ad_base_dn}"
  userattr = "sAMAccountName"

  # Enable UPN domain for login (allows alice@vaultlab.local format)
  upndomain = var.ad_domain_name

  # Group search configuration for AD
  # Use memberOf attribute for group membership
  groupdn     = "CN=Users,${local.ad_base_dn}"
  groupattr   = "cn"
  groupfilter = "(&(objectClass=group)(member:1.2.840.113556.1.4.1941:={{.UserDN}}))"

  # Use AD-specific settings
  use_token_groups = false

  depends_on = [null_resource.wait_for_windows]
}

# Create Vault policy for Vault-Admins group (maps to AD group)
resource "vault_policy" "ldap_admins" {
  count = var.configure_vault_ldap ? 1 : 0

  name = "ldap-admins"
  policy = <<-EOT
    # Vault Policy for AD Admins (Vault-Admins group)
    # Full admin access for troubleshooting and testing

    # Full access to all secrets engines
    path "+/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # Manage auth methods
    path "auth/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }

    path "sys/auth" {
      capabilities = ["read", "list"]
    }

    path "sys/auth/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }

    # List and manage secrets engines (required for UI)
    path "sys/mounts" {
      capabilities = ["read", "list"]
    }

    path "sys/mounts/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # System health and status
    path "sys/health" {
      capabilities = ["read"]
    }

    path "sys/leader" {
      capabilities = ["read"]
    }

    # Policies management
    path "sys/policies/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    path "sys/policies/acl/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # Token management
    path "auth/token/*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
  EOT

  depends_on = [vault_ldap_auth_backend.ad]
}

# Create Vault policy for Vault-Users group
resource "vault_policy" "ldap_users" {
  count = var.configure_vault_ldap ? 1 : 0

  name = "ldap-users"
  policy = <<-EOT
    # Read-only access to secrets
    path "secret/data/*" {
      capabilities = ["read", "list"]
    }

    path "secret/metadata/*" {
      capabilities = ["list"]
    }

    # Read own token info
    path "auth/token/lookup-self" {
      capabilities = ["read"]
    }
  EOT

  depends_on = [vault_ldap_auth_backend.ad]
}

# Map AD group Vault-Admins to Vault policies
resource "vault_ldap_auth_backend_group" "admins" {
  count = var.configure_vault_ldap ? 1 : 0

  backend   = vault_ldap_auth_backend.ad[0].path
  groupname = "Vault-Admins"
  policies  = ["ldap-admins", "default"]

  depends_on = [vault_ldap_auth_backend.ad]
}

# Map AD group Vault-Users to Vault policies
resource "vault_ldap_auth_backend_group" "users" {
  count = var.configure_vault_ldap ? 1 : 0

  backend   = vault_ldap_auth_backend.ad[0].path
  groupname = "Vault-Users"
  policies  = ["ldap-users", "default"]

  depends_on = [vault_ldap_auth_backend.ad]
}
