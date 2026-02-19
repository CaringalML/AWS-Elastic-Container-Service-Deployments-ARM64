# 1. The Missing Piece: ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for ALB - Allows public web traffic"
  vpc_id      = aws_vpc.main.id

  # Allow HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (so it can talk to your tasks)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# 2. The Task Security Group (The "Lock")
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Security group for ECS Tasks - allows traffic ONLY from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow app port ONLY from ALB SG"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # This is why the error happened
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ecs-tasks-sg" }
}

# 3. The Instance Security Group (The Host)
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