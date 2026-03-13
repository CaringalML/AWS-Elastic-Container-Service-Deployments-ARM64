# ==============================================================================
# TASK DEFINITION - Container Specification
# ==============================================================================
# Defines what runs inside each ECS task:
#   - ARM64 (Graviton) runtime for cost savings
#   - awsvpc network mode (each task = its own ENI + private IP)
#   - CloudWatch Logs for container stdout/stderr
#
# Two IAM roles are attached:
#   - execution_role: used by the ECS agent to pull images and push logs
#   - task_role:      used by the application code inside the container
# ==============================================================================

resource "aws_ecs_task_definition" "main" {
  family                   = var.project_name
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc" # Each task gets its own ENI and private IP
  cpu                      = var.task_cpu    # 256 = 0.25 vCPU
  memory                   = var.task_memory # 512 MB
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  # Specifies Graviton (ARM64) so ECS schedules tasks only on ARM64 EC2 instances.
  # The AMI in cluster.tf is also ARM64 — these must always match.
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = var.project_name
      image     = var.container_image
      essential = true # If this container exits, the entire task is stopped

      portMappings = [
        {
          # In awsvpc mode, containerPort and hostPort are always the same.
          # No host port conflicts because each task has its own network namespace.
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      # Ship container logs to CloudWatch Logs.
      # Log group is created in cloudwatch.tf with a 7-day retention policy.
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}
