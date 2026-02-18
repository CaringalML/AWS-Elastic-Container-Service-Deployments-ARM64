resource "aws_lb" "main" {
  name               = var.project_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "main" {
  name        = "${var.project_name}-tg"
  port        = var.host_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance" # bridge mode uses instance target type, not ip

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# Attach ASG to ALB target group
# ECS registers/deregisters EC2 instances automatically
resource "aws_autoscaling_attachment" "ecs" {
  autoscaling_group_name = aws_autoscaling_group.ecs.name
  lb_target_group_arn    = aws_lb_target_group.main.arn
}
