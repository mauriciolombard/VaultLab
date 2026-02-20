variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "vaultlab-secondary"
}

variable "vault_version" {
  description = "Version of Vault to install"
  type        = string
  default     = "1.20.2+ent"
}

variable "vault_license" {
  description = "Vault Enterprise license string"
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type for Vault nodes"
  type        = string
  default     = "t3.micro"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_vault_cidrs" {
  description = "CIDR blocks allowed for Vault API access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Primary Cluster Variables (for VPC Peering)
variable "primary_vpc_id" {
  description = "VPC ID of the primary cluster for peering"
  type        = string
}

variable "primary_vpc_cidr" {
  description = "CIDR block of primary cluster VPC for replication access"
  type        = string
  default     = "10.0.0.0/16"
}
