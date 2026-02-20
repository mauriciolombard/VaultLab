output "vault_nlb_dns" {
  description = "DNS name of the Network Load Balancer"
  value       = aws_lb.vault.dns_name
}

output "vault_addr" {
  description = "VAULT_ADDR environment variable value"
  value       = "http://${aws_lb.vault.dns_name}:8200"
}

output "vault_instance_ips" {
  description = "Public IP addresses of Vault instances"
  value = {
    for i, instance in aws_instance.vault : "vault${i + 1}" => {
      public_ip  = instance.public_ip
      private_ip = instance.private_ip
    }
  }
}

output "vault_instance_ids" {
  description = "Instance IDs of Vault nodes"
  value       = aws_instance.vault[*].id
}

output "kms_key_id" {
  description = "KMS Key ID used for auto-unseal"
  value       = aws_kms_key.vault_unseal.key_id
}

output "ssh_private_key_file" {
  description = "Path to the SSH private key file"
  value       = local_file.private_key.filename
}

output "ssh_connection_commands" {
  description = "SSH commands to connect to each Vault instance"
  value = {
    for i, instance in aws_instance.vault :
    "vault${i + 1}" => "ssh -i ${local_file.private_key.filename} ubuntu@${instance.public_ip}"
  }
}

output "vault_init_command" {
  description = "Command to initialize Vault (run on first node only)"
  value       = "vault operator init"
}

output "export_vault_addr" {
  description = "Export command for VAULT_ADDR"
  value       = "export VAULT_ADDR=http://${aws_lb.vault.dns_name}:8200"
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.vault.id
}

output "vpc_cidr" {
  description = "VPC CIDR block for cross-cluster configuration"
  value       = aws_vpc.vault.cidr_block
}

output "vault_security_group_id" {
  description = "Security group ID for cross-cluster configuration"
  value       = aws_security_group.vault.id
}

output "route_table_id" {
  description = "Route table ID for VPC peering routes"
  value       = aws_route_table.public.id
}
