# MongoDB Server EC2 Instance

resource "aws_instance" "mongodb" {
  ami                         = data.aws_ami.hc_base_ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.available.ids[0]
  vpc_security_group_ids      = [aws_security_group.mongodb.id]
  key_name                    = aws_key_pair.mongodb.key_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/mongodb-user-data.sh", {
    mongodb_admin_password = random_password.mongodb_admin.result
    mongodb_db_name        = var.mongodb_db_name
  })

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.cluster_name}-mongodb"
  }
}

# Wait for MongoDB to be ready before configuring Vault
# This uses remote-exec to actively verify MongoDB accepts connections
resource "null_resource" "mongodb_ready" {
  depends_on = [aws_instance.mongodb]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.mongodb.private_key_pem
    host        = aws_instance.mongodb.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "sudo cloud-init status --wait || true",
      "echo 'Cloud-init finished. Checking MongoDB...'",
      "for i in {1..30}; do",
      "  if mongosh --quiet --eval 'db.runCommand({ping:1})' mongodb://localhost:27017/admin 2>/dev/null | grep -q 'ok'; then",
      "    echo 'MongoDB is ready!'",
      "    exit 0",
      "  fi",
      "  echo \"Attempt $i/30: MongoDB not ready yet, waiting...\"",
      "  sleep 5",
      "done",
      "echo 'MongoDB readiness check failed. Debug info:'",
      "sudo cat /var/log/user-data.log 2>/dev/null | tail -50 || echo 'No user-data log'",
      "sudo systemctl status mongod 2>/dev/null || echo 'mongod service not found'",
      "exit 1"
    ]
  }
}
