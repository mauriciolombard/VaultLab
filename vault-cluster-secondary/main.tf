terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "VaultLab"
      Environment = "lab"
      Component   = "vault-cluster-secondary"
      ManagedBy   = "terraform"
    }
  }
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Get latest HashiCorp Base Ubuntu 24.04 AMI (from ami-prod account)
data "aws_ami" "hc_base_ubuntu" {
  most_recent = true
  owners      = ["888995627335"]

  filter {
    name   = "name"
    values = ["hc-base-ubuntu-2404-amd64-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# SSH Key Pair
resource "tls_private_key" "vault" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "vault" {
  key_name   = "${var.cluster_name}-key"
  public_key = tls_private_key.vault.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.vault.private_key_pem
  filename        = "${path.module}/vault-key.pem"
  file_permission = "0600"
}
