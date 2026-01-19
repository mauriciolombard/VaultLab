# Vault LDAP Authentication Configuration

locals {
  ldap_base_dn = "dc=${replace(var.ldap_domain, ".", ",dc=")}"
}

# Configure LDAP auth method (this also enables the auth backend)
resource "vault_ldap_auth_backend" "openldap" {
  count = var.configure_vault_ldap ? 1 : 0

  path        = "ldap"
  description = "LDAP authentication for OpenLDAP"
  url         = "ldap://${aws_instance.openldap.private_ip}:389"
  starttls    = false
  insecure_tls = true

  # Bind credentials (service account for LDAP searches)
  binddn   = "cn=admin,${local.ldap_base_dn}"
  bindpass = var.ldap_admin_password

  # User search configuration
  userdn    = "ou=users,${local.ldap_base_dn}"
  userattr  = "uid"

  # Group search configuration
  groupdn     = "ou=groups,${local.ldap_base_dn}"
  groupattr   = "cn"
  groupfilter = "(member={{.UserDN}})"

  depends_on = [aws_instance.openldap]
}

# Create Vault policy for vault-admins group
resource "vault_policy" "ldap_admins" {
  count = var.configure_vault_ldap ? 1 : 0

  name   = "ldap-admins"
  policy = file("${path.module}/vault-policies/ldap-policy.hcl")

  depends_on = [vault_ldap_auth_backend.openldap]
}

# Create Vault policy for vault-users group
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
  EOT

  depends_on = [vault_ldap_auth_backend.openldap]
}

# Map LDAP group vault-admins to Vault policies
resource "vault_ldap_auth_backend_group" "admins" {
  count = var.configure_vault_ldap ? 1 : 0

  backend  = vault_ldap_auth_backend.openldap[0].path
  groupname = "vault-admins"
  policies  = ["ldap-admins", "default"]

  depends_on = [vault_ldap_auth_backend.openldap]
}

# Map LDAP group vault-users to Vault policies
resource "vault_ldap_auth_backend_group" "users" {
  count = var.configure_vault_ldap ? 1 : 0

  backend  = vault_ldap_auth_backend.openldap[0].path
  groupname = "vault-users"
  policies  = ["ldap-users", "default"]

  depends_on = [vault_ldap_auth_backend.openldap]
}
