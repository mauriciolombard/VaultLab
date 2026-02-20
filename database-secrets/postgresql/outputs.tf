# Outputs for PostgreSQL Integration

output "postgresql_server_public_ip" {
  description = "Public IP address of the PostgreSQL server"
  value       = aws_instance.postgresql.public_ip
}

output "postgresql_server_private_ip" {
  description = "Private IP address of the PostgreSQL server"
  value       = aws_instance.postgresql.private_ip
}

output "postgresql_connection_string" {
  description = "PostgreSQL connection string (for direct access)"
  value       = "postgresql://vault_admin@${aws_instance.postgresql.private_ip}:5432/${var.postgres_db_name}"
}

output "ssh_connection_command" {
  description = "SSH command to connect to the PostgreSQL server"
  value       = "ssh -i ${path.module}/postgresql-key.pem ubuntu@${aws_instance.postgresql.public_ip}"
}

output "ssh_private_key_file" {
  description = "Path to the SSH private key file"
  value       = local_file.private_key.filename
}

output "vault_mount_path" {
  description = "Vault mount path for PostgreSQL database secrets engine"
  value       = var.configure_vault_db ? vault_mount.postgresql[0].path : "N/A"
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

output "postgres_admin_password" {
  description = "PostgreSQL admin password (for vault_admin user)"
  value       = random_password.postgres_admin.result
  sensitive   = true
}

output "manual_test_1_connectivity" {
  description = "Test database connectivity (run from DB EC2 instance after SSH)"
  value       = "psql -U vault_admin -d ${var.postgres_db_name} -c 'SELECT version();'"
}

output "manual_test_2_vault_creds" {
  description = "Generate and test Vault dynamic credentials"
  value       = "vault read ${var.vault_mount_path}/creds/readonly"
}

output "database_info" {
  description = "Database connection information"
  value = {
    host     = aws_instance.postgresql.private_ip
    port     = 5432
    database = var.postgres_db_name
    username = "vault_admin"
  }
}

output "pre_destroy_cleanup" {
  description = "Run before terraform destroy to avoid lease errors"
  value       = "vault lease revoke -prefix ${var.vault_mount_path}/"
}
