resource "aws_ecr_repository" "employee_crud" {
  name                 = "employee-crud"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags = {
    Name = "employee-crud"
  }
}

resource "aws_ecr_lifecycle_policy" "employee_crud" {
  repository = aws_ecr_repository.employee_crud.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the 2 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 2
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ECR VPC Interface Endpoints for private subnet image pulls
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type = "Interface"
  subnet_ids        = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.ecs_tasks.id]
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type = "Interface"
  subnet_ids        = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.ecs_tasks.id]
}

resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type = "Interface"
  subnet_ids        = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.ecs_tasks.id]
}
