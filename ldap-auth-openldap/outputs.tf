# Outputs for OpenLDAP Integration

output "ldap_server_public_ip" {
  description = "Public IP address of the OpenLDAP server"
  value       = aws_instance.openldap.public_ip
}

output "ldap_server_private_ip" {
  description = "Private IP address of the OpenLDAP server"
  value       = aws_instance.openldap.private_ip
}

output "ldap_url" {
  description = "LDAP URL for Vault configuration"
  value       = "ldap://${aws_instance.openldap.private_ip}:389"
}

output "ldap_base_dn" {
  description = "LDAP Base DN"
  value       = "dc=${replace(var.ldap_domain, ".", ",dc=")}"
}

output "ssh_connection_command" {
  description = "SSH command to connect to the OpenLDAP server"
  value       = "ssh -i ${path.module}/ldap-key.pem ec2-user@${aws_instance.openldap.public_ip}"
}

output "ssh_private_key_file" {
  description = "Path to the SSH private key file"
  value       = local_file.private_key.filename
}

output "test_ldapsearch_command" {
  description = "ldapsearch command to test LDAP connectivity"
  value       = "ldapsearch -x -H ldap://${aws_instance.openldap.public_ip}:389 -b 'dc=${replace(var.ldap_domain, ".", ",dc=")}' -D 'cn=admin,dc=${replace(var.ldap_domain, ".", ",dc=")}' -w '${var.ldap_admin_password}'"
  sensitive   = true
}

output "vault_ldap_login_alice" {
  description = "Vault login command for test user alice (vault-admins group)"
  value       = "vault login -method=ldap username=alice password=${var.ldap_test_user_password}"
  sensitive   = true
}

output "vault_ldap_login_bob" {
  description = "Vault login command for test user bob (vault-users group)"
  value       = "vault login -method=ldap username=bob password=${var.ldap_test_user_password}"
  sensitive   = true
}

output "ldap_test_users" {
  description = "List of test users created in LDAP"
  value = {
    alice   = "member of vault-admins"
    bob     = "member of vault-users"
    charlie = "member of vault-users"
  }
}
