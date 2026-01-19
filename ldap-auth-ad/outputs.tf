# Outputs for Active Directory Integration

output "ad_server_public_ip" {
  description = "Public IP address of the Windows AD server"
  value       = aws_instance.windows_ad.public_ip
}

output "ad_server_private_ip" {
  description = "Private IP address of the Windows AD server"
  value       = aws_instance.windows_ad.private_ip
}

output "ldap_url" {
  description = "LDAP URL for Vault configuration"
  value       = "ldap://${aws_instance.windows_ad.private_ip}:389"
}

output "ad_domain" {
  description = "Active Directory domain name"
  value       = var.ad_domain_name
}

output "ad_base_dn" {
  description = "AD Base DN for LDAP queries"
  value       = "DC=${replace(var.ad_domain_name, ".", ",DC=")}"
}

output "windows_admin_password" {
  description = "Windows Administrator password"
  value       = local.windows_admin_password
  sensitive   = true
}

output "rdp_connection_info" {
  description = "RDP connection information"
  value       = <<-EOT
    Host: ${aws_instance.windows_ad.public_ip}
    Username: Administrator
    Password: Run 'terraform output -raw windows_admin_password'
  EOT
}

output "private_key_file" {
  description = "Path to the private key file (for decrypting Windows password if needed)"
  value       = local_file.private_key.filename
}

output "test_ldapsearch_command" {
  description = "ldapsearch command to test AD LDAP connectivity"
  value       = <<-EOT
    ldapsearch -x -H ldap://${aws_instance.windows_ad.public_ip}:389 \
      -D "CN=vault-svc,CN=Users,DC=${replace(var.ad_domain_name, ".", ",DC=")}" \
      -w "${var.ad_admin_password}" \
      -b "DC=${replace(var.ad_domain_name, ".", ",DC=")}" \
      "(objectClass=user)" sAMAccountName
  EOT
  sensitive   = true
}

output "vault_ldap_login_alice" {
  description = "Vault login command for test user alice (Domain Admins)"
  value       = "vault login -method=ldap username=alice password=${var.ad_test_user_password}"
  sensitive   = true
}

output "vault_ldap_login_bob" {
  description = "Vault login command for test user bob (Domain Users)"
  value       = "vault login -method=ldap username=bob password=${var.ad_test_user_password}"
  sensitive   = true
}

output "ad_test_users" {
  description = "List of test users created in Active Directory"
  value = {
    alice   = "member of Vault-Admins (maps to ldap-admins policy)"
    bob     = "member of Vault-Users (maps to ldap-users policy)"
    charlie = "member of Vault-Users (maps to ldap-users policy)"
  }
}

output "ad_service_account" {
  description = "AD service account used by Vault for LDAP bind"
  value       = "vault-svc"
}

output "important_notes" {
  description = "Important setup notes"
  value       = <<-EOT

    IMPORTANT: Windows AD setup takes 10-15 minutes after EC2 launch.

    1. Wait for the server to fully initialize before testing
    2. AD DS installation and promotion happen automatically via user-data
    3. Test users (alice, bob, charlie) are created after AD promotion
    4. Vault LDAP auth is configured automatically if configure_vault_ldap=true

    To verify AD is ready:
    - RDP to the server and check Server Manager
    - Or test with: ldapsearch -x -H ldap://${aws_instance.windows_ad.public_ip}:389 -b "" -s base
  EOT
}
