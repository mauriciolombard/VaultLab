# Security Groups for OpenLDAP Server

resource "aws_security_group" "ldap" {
  name        = "${var.cluster_name}-ldap-sg"
  description = "Security group for OpenLDAP server"
  vpc_id      = data.aws_vpc.selected.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # LDAP (unencrypted)
  ingress {
    description = "LDAP"
    from_port   = 389
    to_port     = 389
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_ldap_cidrs) > 0 ? var.allowed_ldap_cidrs : [data.aws_vpc.selected.cidr_block]
  }

  # LDAPS (TLS encrypted)
  ingress {
    description = "LDAPS"
    from_port   = 636
    to_port     = 636
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_ldap_cidrs) > 0 ? var.allowed_ldap_cidrs : [data.aws_vpc.selected.cidr_block]
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-ldap-sg"
  }
}
