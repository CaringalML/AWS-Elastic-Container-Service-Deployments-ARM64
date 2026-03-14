# ------------------------------------------------------------------------------
# HTTPS Listener (port 443)
# Forwards HTTPS traffic to the target group using ACM certificate
# ------------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# ------------------------------------------------------------------------------
# HTTP Listener (port 80) with redirect to HTTPS
# ------------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
# ==============================================================================
# ALB - Application Load Balancer
# ==============================================================================
# Sits in front of the ECS tasks and distributes HTTP traffic.
#
# Target type is "ip" (not "instance") because ECS tasks run in awsvpc mode —
# each task gets its own ENI with a private IP, so the ALB routes directly to
# task IPs rather than to the EC2 instance ports.
#
# aws_autoscaling_attachment is NOT used here because in awsvpc mode ECS
# registers/deregisters task IPs with the target group automatically.
# ==============================================================================

resource "aws_lb" "main" {
  name               = var.project_name
  internal           = false          # Internet-facing ALB
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id # Deployed across all public subnets

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# ------------------------------------------------------------------------------
# Target Group
# Receives forwarded requests from the listener and routes them to task IPs.
# Health checks poll "/" every 30 seconds; 2 failures → unhealthy,
# 3 successes → healthy again.
# ------------------------------------------------------------------------------
resource "aws_lb_target_group" "main" {
  name        = "${var.project_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Required for awsvpc mode to route to Task IPs

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

# NOTE: aws_autoscaling_attachment is no longer required for awsvpc mode
# as ECS registers individual Task IPs with the target group directly.
