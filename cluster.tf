# 1. Fetch the latest ECS-optimized Amazon Linux 2023 ARM64 AMI
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
}

# 2. Launch Template
resource "aws_launch_template" "ecs" {
  name_prefix = "${var.project_name}-ecs-lt-"
  image_id    = data.aws_ssm_parameter.ecs_ami.value

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ecs_instances.id]
  }

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
    create_before_destroy = true
  }
}

# 3. Auto Scaling Group (Pure Spot Configuration)
resource "aws_autoscaling_group" "ecs" {
  name                = "${var.project_name}-ecs-asg"
  vpc_zone_identifier = aws_subnet.public[*].id
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  
  protect_from_scale_in = true 

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "price-capacity-optimized"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ecs.id
        version            = "$Latest"
      }
      
      override { instance_type = "t4g.micro" }
      override { instance_type = "t4g.small" }
      override { instance_type = "t4g.medium" }
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-ecs-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }

  depends_on = [aws_internet_gateway.main]

  lifecycle {
    # FIX: Prevents Terraform from resetting the instance count during apply
    ignore_changes        = [desired_capacity]
    create_before_destroy = true
  }
}

# 4. ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = var.project_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# 5. Capacity Provider
resource "aws_ecs_capacity_provider" "self_managed" {
  name = "${var.project_name}-self-managed-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "ENABLED"
    managed_draining               = "ENABLED"

    managed_scaling {
      maximum_scaling_step_size = 5
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
      instance_warmup_period    = 60 
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 6. Cluster Association
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.self_managed.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.self_managed.name
    base              = 0
    weight            = 1
  }
}