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
      image     = "${aws_ecr_repository.employee_crud.repository_url}:latest"
      essential = true

      # Give the container 60s to boot before health checks start counting
      healthCheck = {
        command     = ["CMD-SHELL", "curl -sf http://localhost/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # Non-sensitive Laravel environment variables
      environment = [
        { name = "APP_NAME",          value = var.project_name },
        { name = "APP_ENV",           value = var.app_env },
        { name = "APP_DEBUG",         value = tostring(var.app_debug) },
        { name = "APP_URL",           value = "https://${var.domain_name}" },
        { name = "DB_CONNECTION",     value = "pgsql" },
        { name = "LOG_CHANNEL",       value = "stack" },
        { name = "LOG_STACK",         value = "single" },
        { name = "LOG_LEVEL",         value = var.log_level },
        { name = "SESSION_DRIVER",    value = "database" },
        { name = "SESSION_LIFETIME",  value = "120" },
        { name = "QUEUE_CONNECTION",  value = "database" },
        { name = "CACHE_STORE",       value = "database" },
        { name = "FILESYSTEM_DISK",    value = "s3" },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
        { name = "AWS_BUCKET",         value = aws_s3_bucket.media.bucket },
        { name = "AWS_URL",            value = "https://cdn.${var.domain_name}" },
      ]

      # Sensitive values pulled from Secrets Manager at task launch.
      # Syntax: "<secret_arn>:<json_key>::" extracts a single key from a JSON secret.
      secrets = [
        {
          name      = "APP_KEY"
          valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:app_key::"
        },
        {
          name      = "DB_USERNAME"
          valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:password::"
        },
        {
          name      = "DB_HOST"
          valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:host::"
        },
        {
          name      = "DB_PORT"
          valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:port::"
        },
        {
          name      = "DB_DATABASE"
          valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:dbname::"
        }
      ]
    }
  ])
}
