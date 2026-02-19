resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count

  # Network configuration required for awsvpc mode
  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false # Must be false for EC2 launch type
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.self_managed.name
    base              = 0
    weight            = 1
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = var.project_name
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = 60

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy,
    aws_ecs_cluster_capacity_providers.main,
    # aws_autoscaling_attachment removed as it's not used with 'ip' target type
    aws_internet_gateway.main 
  ]

  lifecycle {
    ignore_changes = [desired_count]
  }
}