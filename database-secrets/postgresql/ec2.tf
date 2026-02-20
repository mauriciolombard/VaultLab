# PostgreSQL Server EC2 Instance

resource "aws_instance" "postgresql" {
  ami                         = data.aws_ami.hc_base_ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.available.ids[0]
  vpc_security_group_ids      = [aws_security_group.postgresql.id]
  key_name                    = aws_key_pair.postgresql.key_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/postgresql-user-data.sh", {
    postgres_password = random_password.postgres_admin.result
    postgres_db_name  = var.postgres_db_name
  })

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.cluster_name}-postgresql"
  }

  # Wait for instance to be ready before configuring Vault
  provisioner "local-exec" {
    command = "echo 'Waiting for PostgreSQL server to initialize...' && sleep 90"
  }
}
