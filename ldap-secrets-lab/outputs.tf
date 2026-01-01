output "vault_addr" {
  description = "VAULT_ADDR environment variable value"
  value       = "http://${aws_instance.vault.public_ip}:8200"
}

output "export_vault_addr" {
  description = "Export command for VAULT_ADDR"
  value       = "export VAULT_ADDR=http://${aws_instance.vault.public_ip}:8200"
}

output "vault_instance" {
  description = "Vault instance details"
  value = {
    public_ip  = aws_instance.vault.public_ip
    private_ip = aws_instance.vault.private_ip
  }
}

output "ldap_instance" {
  description = "OpenLDAP instance details"
  value = {
    public_ip  = aws_instance.ldap.public_ip
    private_ip = aws_instance.ldap.private_ip
  }
}

output "ldap_connection" {
  description = "LDAP connection details"
  value = {
    ldap_url         = "ldap://${aws_instance.ldap.private_ip}:389"
    ldaps_url        = "ldaps://${aws_instance.ldap.private_ip}:636"
    base_dn          = local.ldap_base_dn
    admin_dn         = "cn=admin,${local.ldap_base_dn}"
    phpldapadmin_url = "http://${aws_instance.ldap.public_ip}:8080"
  }
}

output "kms_key_id" {
  description = "KMS Key ID used for auto-unseal"
  value       = aws_kms_key.vault_unseal.key_id
}

output "ssh_private_key_file" {
  description = "Path to the SSH private key file"
  value       = local_file.private_key.filename
}

output "ssh_vault" {
  description = "SSH command to connect to Vault instance"
  value       = "ssh -i ${local_file.private_key.filename} ec2-user@${aws_instance.vault.public_ip}"
}

output "ssh_ldap" {
  description = "SSH command to connect to LDAP instance"
  value       = "ssh -i ${local_file.private_key.filename} ec2-user@${aws_instance.ldap.public_ip}"
}

output "vault_init_command" {
  description = "Command to initialize Vault"
  value       = "vault operator init"
}

output "quick_start" {
  description = "Quick start instructions"
  value       = <<-EOT

    === Quick Start Guide ===

    1. SSH to Vault:
       ${local_file.private_key.filename} permissions should be 0600
       ssh -i ${local_file.private_key.filename} ec2-user@${aws_instance.vault.public_ip}

    2. Initialize Vault:
       vault operator init

    3. Set VAULT_TOKEN (use root token from init):
       export VAULT_TOKEN=<root-token>

    4. Configure LDAP secrets engine:
       ~/scripts/configure-ldap-secrets.sh

    5. phpLDAPadmin UI:
       http://${aws_instance.ldap.public_ip}:8080
       Login: cn=admin,${local.ldap_base_dn}
       Password: (value of ldap_admin_password variable)

    6. From your local machine, export VAULT_ADDR:
       export VAULT_ADDR=http://${aws_instance.vault.public_ip}:8200

  EOT
}
