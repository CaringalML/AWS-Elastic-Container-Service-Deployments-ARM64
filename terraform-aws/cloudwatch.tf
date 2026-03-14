# ==============================================================================
# CLOUDWATCH - Logging & Alarms
# ==============================================================================
# This file defines:
#   - A CloudWatch Log Group for ECS container logs
#   - SNS topic + email subscription for alarm notifications
#   - Alarms for ALB health and ECS service health/resource usage
# ==============================================================================

# ------------------------------------------------------------------------------
# Log Group
# Stores stdout/stderr from ECS containers. Retention is kept short (7 days)
# to minimise CloudWatch Logs storage costs in a dev environment.
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
  skip_destroy      = var.log_group_skip_destroy

  tags = {
    Name = "${var.project_name}-log-group"
  }
}

# ------------------------------------------------------------------------------
# SNS Topic & Email Subscription
# All CloudWatch alarms below send to this topic.
# AWS will send a confirmation email to the address - you MUST click the link
# before any notifications are delivered.
# ------------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"

  tags = {
    Name = "${var.project_name}-alerts"
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ------------------------------------------------------------------------------
# Alarm: ALB Unhealthy Hosts
# Fires when any registered target in the target group fails its health check.
# This usually means the container crashed or is not responding on port 80.
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${var.project_name}-alb-unhealthy-hosts"
  alarm_description   = "ALB target group has unhealthy hosts - container may be down"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.project_name}-alb-unhealthy-hosts"
  }
}

# ------------------------------------------------------------------------------
# Alarm: ALB 5xx Errors
# Fires when the load balancer itself returns more than 10 server-side errors
# within a 60-second window. Spikes here often indicate app crashes or
# upstream task failures that the ALB cannot route around.
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${var.project_name}-alb-5xx-errors"
  alarm_description   = "ALB is returning elevated 5xx errors"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching" # No traffic = no errors, don't alarm

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.project_name}-alb-5xx-errors"
  }
}

# ------------------------------------------------------------------------------
# Alarm: ECS Running Task Count
# Fires when fewer tasks are running than expected (threshold = 1).
# Requires Container Insights to be enabled on the cluster (already set in
# cluster.tf). treat_missing_data = "breaching" ensures an alarm is raised
# if metrics stop arriving entirely (e.g. the cluster itself is gone).
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks" {
  alarm_name          = "${var.project_name}-ecs-low-running-tasks"
  alarm_description   = "ECS running task count dropped below 1 - service may be down"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.main.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.project_name}-ecs-low-running-tasks"
  }
}

# ------------------------------------------------------------------------------
# Alarm: ECS CPU Utilization
# Fires when average CPU across all tasks exceeds 80% for 3 consecutive minutes.
# With t4g.micro (2 vCPU shared), sustained high CPU often precedes OOM kills
# or throttling. Consider scaling out or upsizing the task CPU if this fires
# regularly.
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.project_name}-ecs-cpu-high"
  alarm_description   = "ECS service CPU utilization is above 80%"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "CpuUtilized"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.main.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.project_name}-ecs-cpu-high"
  }
}

# ------------------------------------------------------------------------------
# Alarm: ECS Memory Utilization
# Fires when average memory across all tasks exceeds 80% for 3 consecutive
# minutes. The task is allocated 512 MB (task_memory variable). Crossing 80%
# (~410 MB) is an early warning before the container is OOM-killed by ECS.
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "${var.project_name}-ecs-memory-high"
  alarm_description   = "ECS service memory utilization is above 80%"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "MemoryUtilized"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.main.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.project_name}-ecs-memory-high"
  }
}
