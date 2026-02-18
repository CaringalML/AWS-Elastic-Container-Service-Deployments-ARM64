resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
  skip_destroy      = var.log_group_skip_destroy

  tags = {
    Name = "${var.project_name}-log-group"
  }
}
