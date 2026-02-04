# Outputs for MySQL Integration

output "mysql_server_public_ip" {
  description = "Public IP address of the MySQL server"
  value       = aws_instance.mysql.public_ip
}

output "mysql_server_private_ip" {
  description = "Private IP address of the MySQL server"
  value       = aws_instance.mysql.private_ip
}

output "mysql_connection_string" {
  description = "MySQL connection string (for direct access)"
  value       = "mysql -h ${aws_instance.mysql.private_ip} -u vault_admin -p${var.mysql_db_name}"
}

output "ssh_connection_command" {
  description = "SSH command to connect to the MySQL server"
  value       = "ssh -i ${path.module}/mysql-key.pem ec2-user@${aws_instance.mysql.public_ip}"
}

output "ssh_private_key_file" {
  description = "Path to the SSH private key file"
  value       = local_file.private_key.filename
}

output "vault_mount_path" {
  description = "Vault mount path for MySQL database secrets engine"
  value       = var.configure_vault_db ? vault_mount.mysql[0].path : "N/A"
}

output "vault_generate_readonly_creds" {
  description = "Vault command to generate readonly credentials"
  value       = "vault read ${var.vault_mount_path}/creds/readonly"
}

output "vault_generate_readwrite_creds" {
  description = "Vault command to generate readwrite credentials"
  value       = "vault read ${var.vault_mount_path}/creds/readwrite"
}

output "vault_generate_admin_creds" {
  description = "Vault command to generate admin credentials"
  value       = "vault read ${var.vault_mount_path}/creds/admin"
}

output "mysql_admin_password" {
  description = "MySQL root password (for vault_admin user)"
  value       = random_password.mysql_root.result
  sensitive   = true
}

output "manual_test_1_connectivity" {
  description = "Test database connectivity (run from DB EC2 instance after SSH)"
  value       = "mysql -u vault_admin -p -e 'SELECT version();'"
}

output "manual_test_2_vault_creds" {
  description = "Generate and test Vault dynamic credentials"
  value       = "vault read ${var.vault_mount_path}/creds/readonly"
}

output "database_info" {
  description = "Database connection information"
  value = {
    host     = aws_instance.mysql.private_ip
    port     = 3306
    database = var.mysql_db_name
    username = "vault_admin"
  }
}

output "pre_destroy_cleanup" {
  description = "Run before terraform destroy to avoid lease errors"
  value       = "vault lease revoke -prefix ${var.vault_mount_path}/"
}
