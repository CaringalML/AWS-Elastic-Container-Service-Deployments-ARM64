# ==============================================================================
# ECS SERVICE - Self-Managed (EC2 Launch Type via Capacity Provider)
# ==============================================================================
# Defines the ECS service that keeps the desired number of tasks running,
# handles rolling deployments, and registers tasks with the ALB target group.
#
# Network mode is awsvpc: each task gets its own ENI with a dedicated private
# IP. The ALB routes directly to these IPs (target type = "ip").
#
# assign_public_ip = false is mandatory for EC2 launch type — only Fargate
# tasks can be assigned public IPs in awsvpc mode.
# ==============================================================================

resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count

  # REQUIRED for awsvpc network mode — tasks need subnet and SG assignment
  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false # Must be false for EC2 launch type
  }

  # Use the self-managed capacity provider (backed by the mixed On-Demand + Spot ASG).
  # base = 1 ensures at least 1 task always runs on this provider.
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.self_managed.name
    base              = 1
    weight            = 1
  }

  # ECS automatically registers/deregisters task IPs with the target group
  # when tasks start and stop (no autoscaling_attachment needed).
  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = var.project_name
    container_port   = var.container_port
  }

  # Grace period gives the container time to start before ALB health checks
  # begin failing and potentially killing the task prematurely.
  health_check_grace_period_seconds = 60

  # Rolling deployment: keep 100% healthy tasks running at all times,
  # allow up to 200% (double tasks) briefly during the rollout.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  depends_on = [
    aws_lb_listener.http,                              # ALB must be ready before tasks register
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy,
    aws_ecs_cluster_capacity_providers.main,           # Capacity provider must be associated first
    aws_internet_gateway.main                          # Instances need internet for image pulls
  ]

  lifecycle {
    # Let the ECS Capacity Provider manage desired_count — Terraform should not
    # reset it to the variable value on every apply.
    ignore_changes = [desired_count]
  }
}
