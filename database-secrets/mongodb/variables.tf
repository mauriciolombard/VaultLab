variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "vaultlab"
}

variable "vpc_id" {
  description = "VPC ID where MongoDB server will be deployed (use VPC from awskms-autounseal)"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the MongoDB server (optional - will use first available if not specified)"
  type        = string
  default     = ""
}

variable "vault_addr" {
  description = "VAULT_ADDR of the existing Vault cluster (e.g., http://nlb-dns:8200)"
  type        = string
}

variable "vault_token" {
  description = "Vault token with permissions to configure database secrets engine"
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type for MongoDB server (t3.small recommended for memory)"
  type        = string
  default     = "t3.small"  # MongoDB needs more memory
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_db_cidrs" {
  description = "CIDR blocks allowed for database access (default: VPC CIDR)"
  type        = list(string)
  default     = []
}

variable "mongodb_db_name" {
  description = "Name of the database to create"
  type        = string
  default     = "vaultdb"
}

variable "configure_vault_db" {
  description = "Whether to automatically configure Vault database secrets engine"
  type        = bool
  default     = true
}

variable "vault_mount_path" {
  description = "Mount path for the database secrets engine"
  type        = string
  default     = "database/mongodb"
}

variable "default_ttl" {
  description = "Default TTL for dynamic credentials (seconds)"
  type        = number
  default     = 3600  # 1 hour
}

variable "max_ttl" {
  description = "Maximum TTL for dynamic credentials (seconds)"
  type        = number
  default     = 86400  # 24 hours
}
