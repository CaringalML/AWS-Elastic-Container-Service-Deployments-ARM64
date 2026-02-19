# 1. ALB Security Group (The Front Gate)
# Allows public traffic only on standard web ports
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for ALB - allows public HTTP traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Public HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# 2. ECS Task Security Group (The "Lockdown" Layer)
# Used only when network_mode = "awsvpc"
# Only allows traffic from the ALB's Security Group
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Security group for ECS Tasks - allows traffic ONLY from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow traffic ONLY from ALB SG"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # This is the lock
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ecs-tasks-sg" }
}

# 3. EC2 Instance Security Group (Infrastructure Only)
# Since you're using awsvpc, your app traffic DOES NOT go through this SG.
resource "aws_security_group" "ecs_instances" {
  name        = "${var.project_name}-ecs-instances-sg"
  description = "Security group for EC2 hosts - No public app ports needed"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ecs-instances-sg" }
}