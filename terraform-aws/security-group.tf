# ==============================================================================
# SECURITY GROUPS - Layered Network Access Control
# ==============================================================================
# Three security groups form a chain, each narrower than the last:
#
#   Internet → [ALB SG] → [ECS Tasks SG] → [DB SG]
#
# - ALB SG: Allows HTTP from anywhere, egress to anywhere
# - ECS Tasks SG: Allows HTTP only from ALB SG, egress to anywhere, ingress to DB SG
# - DB SG: Allows Postgres only from ECS Tasks SG
#
# The ECS Tasks SG only accepts traffic FROM the ALB SG, and the DB SG only from ECS Tasks SG.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. ALB Security Group (The Front Gate)
# Accepts HTTP traffic from the public internet and forwards it to the tasks.
# All egress is open so the ALB can reach task IPs in any subnet.
# ------------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for ALB - allows public HTTP/HTTPS traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Public HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Public HTTPS from internet"
    from_port   = 443
    to_port     = 443
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

# ------------------------------------------------------------------------------
# 2. ECS Tasks Security Group (The Lockdown Layer)
# Attached to each task's ENI (awsvpc mode gives every task its own ENI).
# Only allows inbound traffic sourced from the ALB security group — not a
# CIDR, but the SG reference itself, so only ALB-originated connections pass.
# ------------------------------------------------------------------------------
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Security group for ECS Tasks - allows traffic ONLY from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow traffic only from ALB security group"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # SG reference, not a CIDR — tighter control
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ecs-tasks-sg" }
}

# ------------------------------------------------------------------------------
# 3. EC2 Instance Security Group (Infrastructure Only)
# Attached to the EC2 host, NOT to the container ENIs.
# In awsvpc mode, application traffic bypasses this SG entirely and hits the
# task SG above. This SG is kept minimal — no inbound rules needed because:
#   - SSH is replaced by SSM Session Manager (no port required)
#   - App traffic goes directly to task ENIs
# ------------------------------------------------------------------------------
resource "aws_security_group" "ecs_instances" {
  name        = "${var.project_name}-ecs-instances-sg"
  description = "Security group for EC2 hosts - no public app ports needed in awsvpc mode"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ecs-instances-sg" }
}
