# Security Groups for PostgreSQL Server

resource "aws_security_group" "postgresql" {
  name        = "${var.cluster_name}-postgresql-sg"
  description = "Security group for PostgreSQL server"
  vpc_id      = data.aws_vpc.selected.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # PostgreSQL
  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = length(var.allowed_db_cidrs) > 0 ? var.allowed_db_cidrs : [data.aws_vpc.selected.cidr_block]
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
    Name = "${var.cluster_name}-postgresql-sg"
  }
}
