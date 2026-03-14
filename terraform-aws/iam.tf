# ==============================================================================
# IAM - Roles & Policies
# ==============================================================================
# Three distinct roles follow the principle of least privilege:
#
#   1. Task Execution Role  ("Janitor")  — ECS agent infrastructure tasks
#   2. Task Role            ("Worker")   — permissions for your app code
#   3. EC2 Instance Role    ("Host")     — EC2-level ECS agent + SSM access
#
# The instance profile wraps role #3 so the Launch Template can reference it.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Task Execution Role
# Used by the ECS agent (not your app) to:
#   - Pull the container image from ECR (or Docker Hub via NAT)
#   - Write container logs to CloudWatch Logs
# Attach AmazonECSTaskExecutionRolePolicy — the AWS-managed policy that covers
# exactly these two responsibilities.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ------------------------------------------------------------------------------
# 2. Task Role
# Assumed by the application code running inside the container.
# Grants scoped S3 access to the media bucket so Laravel can read/write files.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# Scoped S3 policy — app can only touch its own media bucket
resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${var.project_name}-ecs-task-s3"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowObjectOperations"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.media.arn}/*"
      },
      {
        Sid      = "AllowBucketList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.media.arn
      },
    ]
  })
}

# ------------------------------------------------------------------------------
# 3. EC2 Instance Role
# Assumed by the EC2 host (not the container). Needs two policies:
#   - AmazonEC2ContainerServiceforEC2Role: lets the ECS agent register the
#     instance with the cluster, poll for tasks, and report health
#   - AmazonSSMManagedInstanceCore: enables AWS Systems Manager Session Manager
#     so you can shell into instances without opening SSH or managing key pairs
# ------------------------------------------------------------------------------
resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.project_name}-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Grants the ECS agent on each EC2 instance permission to manage tasks
resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Enables Session Manager — no SSH key or open inbound port required
resource "aws_iam_role_policy_attachment" "ecs_instance_ssm_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ------------------------------------------------------------------------------
# 4. Instance Profile
# A container that links the EC2 Instance Role to EC2 instances.
# Referenced by the Launch Template — this is how the role is actually applied.
# ------------------------------------------------------------------------------
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${var.project_name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}
