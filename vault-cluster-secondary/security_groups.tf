# Security Group for Vault Instances
resource "aws_security_group" "vault" {
  name        = "${var.cluster_name}-vault-sg"
  description = "Security group for Vault cluster nodes"
  vpc_id      = aws_vpc.vault.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Vault API
  ingress {
    description = "Vault API"
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = var.allowed_vault_cidrs
  }

  # Vault Cluster (internal)
  ingress {
    description = "Vault Cluster"
    from_port   = 8201
    to_port     = 8201
    protocol    = "tcp"
    self        = true
  }

  # All outbound traffic
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-vault-sg"
  }
}

# Allow replication traffic FROM primary cluster VPC (always enabled for replication lab)
resource "aws_security_group_rule" "vault_replication_8200_from_peer" {
  type              = "ingress"
  from_port         = 8200
  to_port           = 8200
  protocol          = "tcp"
  cidr_blocks       = [var.primary_vpc_cidr]
  security_group_id = aws_security_group.vault.id
  description       = "Vault API/replication from primary cluster"
}

resource "aws_security_group_rule" "vault_replication_8201_from_peer" {
  type              = "ingress"
  from_port         = 8201
  to_port           = 8201
  protocol          = "tcp"
  cidr_blocks       = [var.primary_vpc_cidr]
  security_group_id = aws_security_group.vault.id
  description       = "Vault cluster/replication from primary cluster"
}

# Security Group for NLB (allow health checks)
resource "aws_security_group" "nlb" {
  name        = "${var.cluster_name}-nlb-sg"
  description = "Security group for NLB"
  vpc_id      = aws_vpc.vault.id

  ingress {
    description = "Vault API from anywhere"
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = var.allowed_vault_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-nlb-sg"
  }
}
