# Security Groups for MongoDB Server

resource "aws_security_group" "mongodb" {
  name        = "${var.cluster_name}-mongodb-sg"
  description = "Security group for MongoDB server"
  vpc_id      = data.aws_vpc.selected.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # MongoDB
  ingress {
    description = "MongoDB"
    from_port   = 27017
    to_port     = 27017
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
    Name = "${var.cluster_name}-mongodb-sg"
  }
}
