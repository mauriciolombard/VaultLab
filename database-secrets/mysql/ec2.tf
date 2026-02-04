# MySQL Server EC2 Instance

resource "aws_instance" "mysql" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.available.ids[0]
  vpc_security_group_ids      = [aws_security_group.mysql.id]
  key_name                    = aws_key_pair.mysql.key_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/mysql-user-data.sh", {
    mysql_root_password = random_password.mysql_root.result
    mysql_db_name       = var.mysql_db_name
  })

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.cluster_name}-mysql"
  }
}

# Wait for MySQL to be ready before configuring Vault
# This uses remote-exec to actively verify MySQL accepts connections
resource "null_resource" "mysql_ready" {
  depends_on = [aws_instance.mysql]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.mysql.private_key_pem
    host        = aws_instance.mysql.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "sudo cloud-init status --wait || true",
      "echo 'Cloud-init finished. Checking MariaDB...'",
      "if command -v mysqladmin &> /dev/null && mysqladmin ping -h localhost --silent 2>/dev/null; then",
      "  echo 'MariaDB is ready!'",
      "else",
      "  echo 'MariaDB check failed. Debug info:'",
      "  sudo cat /var/log/user-data.log 2>/dev/null | tail -50 || echo 'No user-data log'",
      "  sudo systemctl status mariadb 2>/dev/null || echo 'mariadb service not found'",
      "  exit 1",
      "fi"
    ]
  }
}
