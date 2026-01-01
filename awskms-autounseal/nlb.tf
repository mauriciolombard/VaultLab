# Network Load Balancer
resource "aws_lb" "vault" {
  name               = "${var.cluster_name}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = aws_subnet.public[*].id

  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.cluster_name}-nlb"
  }
}

# Target Group for Vault API
resource "aws_lb_target_group" "vault" {
  name     = "${var.cluster_name}-vault-tg"
  port     = 8200
  protocol = "TCP"
  vpc_id   = aws_vpc.vault.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    port                = 8200
    protocol            = "TCP"
  }

  tags = {
    Name = "${var.cluster_name}-vault-tg"
  }
}

# Register Vault instances with target group
resource "aws_lb_target_group_attachment" "vault" {
  count = 3

  target_group_arn = aws_lb_target_group.vault.arn
  target_id        = aws_instance.vault[count.index].id
  port             = 8200
}

# NLB Listener
resource "aws_lb_listener" "vault" {
  load_balancer_arn = aws_lb.vault.arn
  port              = 8200
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vault.arn
  }

  tags = {
    Name = "${var.cluster_name}-vault-listener"
  }
}
