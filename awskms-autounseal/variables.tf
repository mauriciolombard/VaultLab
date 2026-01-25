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

variable "ami_id" {
  description = "AMI ID for Vault EC2 instances (pinned to prevent unexpected replacements)"
  type        = string
  default     = "ami-0e3008cbd8722baf0" # Amazon Linux 2023 - us-east-1 - Jan 2026
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
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
