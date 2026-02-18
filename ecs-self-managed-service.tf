resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count

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

  # Stabilization settings for updates
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Dependencies to ensure correct order
  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy,
    aws_ecs_cluster_capacity_providers.main,
    aws_autoscaling_attachment.ecs,
    aws_internet_gateway.main 
  ]

  lifecycle {
    # FIX: Prevents Terraform from resetting task counts if changed by AWS scaling
    ignore_changes = [desired_count]
  }
}