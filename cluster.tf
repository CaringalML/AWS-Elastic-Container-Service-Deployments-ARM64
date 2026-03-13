# ==============================================================================
# CLUSTER - ECS Cluster, EC2 Launch Template, ASG & Capacity Provider
# ==============================================================================
# This file wires together the compute layer:
#   1. Fetches the latest ECS-optimized AL2023 ARM64 AMI from SSM (always current)
#   2. Launch Template  — defines how each EC2 instance is configured
#   3. Auto Scaling Group — manages the EC2 fleet with mixed On-Demand + Spot
#   4. ECS Cluster       — logical grouping for tasks and services
#   5. Capacity Provider — links the ASG to ECS so task demand drives scaling
#   6. Cluster Association — binds the capacity provider to the cluster
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Latest ECS-Optimized ARM64 AMI
# Using SSM Parameter Store means Terraform always picks up the current AMI
# without hardcoding an AMI ID that can go stale.
# ------------------------------------------------------------------------------
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
}

# ------------------------------------------------------------------------------
# 2. Launch Template
# Defines the EC2 configuration used by the ASG when launching new instances.
# Key points:
#   - ARM64 architecture (Graviton) — ~30-40% cheaper than equivalent x86
#   - User data registers the instance with the ECS cluster on first boot
#   - create_before_destroy prevents a gap in capacity during LT updates
# ------------------------------------------------------------------------------
resource "aws_launch_template" "ecs" {
  name_prefix = "${var.project_name}-ecs-lt-"
  image_id    = data.aws_ssm_parameter.ecs_ami.value

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true # Needed for SSM access and outbound internet
    security_groups             = [aws_security_group.ecs_instances.id]
  }

  # Bootstraps the ECS agent: sets cluster name and enables task IAM roles
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${var.project_name} >> /etc/ecs/ecs.config
    echo ECS_ENABLE_TASK_IAM_ROLE=true >> /etc/ecs/ecs.config
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project_name}-ecs-instance" }
  }

  lifecycle {
    create_before_destroy = true # Prevents capacity gap during launch template updates
  }
}

# ------------------------------------------------------------------------------
# 3. Auto Scaling Group (Mixed: On-Demand base + Spot scale-out)
# Cost strategy:
#   - 1 On-Demand instance always running (stable base, never interrupted)
#   - All additional capacity uses Spot (up to ~70% cheaper)
#   - price-capacity-optimized strategy balances cost vs. Spot interruption risk
#
# protect_from_scale_in = true is REQUIRED when using ECS Managed Scaling —
# the Capacity Provider controls termination, not the ASG.
#
# ignore_changes = [desired_capacity] prevents Terraform from fighting with
# the ECS Capacity Provider over instance count on every plan/apply.
# ------------------------------------------------------------------------------
resource "aws_autoscaling_group" "ecs" {
  name                = "${var.project_name}-ecs-asg"
  vpc_zone_identifier = aws_subnet.public[*].id
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size

  protect_from_scale_in = true # ECS Capacity Provider manages scale-in, not the ASG

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 1 # Always keep 1 stable On-Demand instance
      on_demand_percentage_above_base_capacity = 0 # All scaling above base uses Spot
      spot_allocation_strategy                 = "price-capacity-optimized"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ecs.id
        version            = "$Latest"
      }

      # Fallback instance types in order of preference (both ARM64/Graviton)
      override { instance_type = "t4g.micro" }
      override { instance_type = "t4g.small" }
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-ecs-instance"
    propagate_at_launch = true
  }

  # Required tag so ECS knows this ASG is managed by a Capacity Provider
  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }

  # IGW must exist before instances can reach the internet (ECR, ECS endpoints)
  depends_on = [aws_internet_gateway.main]

  lifecycle {
    ignore_changes        = [desired_capacity] # Let ECS Capacity Provider own this value
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# 4. ECS Cluster
# Logical grouping for ECS services and tasks. Container Insights provides
# enhanced CloudWatch metrics (CPU, memory, network) used by the alarms in
# cloudwatch.tf — do not disable it.
# ------------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = var.project_name

  setting {
    name  = "containerInsights"
    value = "enabled" # Enables ECS/ContainerInsights metrics for CloudWatch alarms
  }
}

# ------------------------------------------------------------------------------
# 5. Capacity Provider
# Links the ASG to ECS so that task demand automatically triggers EC2 scaling.
# Managed termination protection ensures ECS drains tasks before an instance
# is terminated, preventing dropped requests.
# target_capacity = 100 means scale to exactly meet demand (no spare capacity).
# ------------------------------------------------------------------------------
resource "aws_ecs_capacity_provider" "self_managed" {
  name = "${var.project_name}-self-managed-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "ENABLED" # Prevents terminating instances mid-task
    managed_draining               = "ENABLED" # Gracefully drains tasks before shutdown

    managed_scaling {
      maximum_scaling_step_size = 5    # Add at most 5 instances per scaling event
      minimum_scaling_step_size = 1    # Remove at least 1 instance per scaling event
      status                    = "ENABLED"
      target_capacity           = 100  # Scale to 100% utilization (cost-optimized)
      instance_warmup_period    = 60   # Seconds to wait after launch before scaling again
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# 6. Cluster <> Capacity Provider Association
# Registers the capacity provider with the cluster and sets it as the default
# strategy. base = 1 guarantees at least 1 task always uses this provider.
# ------------------------------------------------------------------------------
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.self_managed.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.self_managed.name
    base              = 1 # Matches the ASG On-Demand base
    weight            = 1
  }
}
