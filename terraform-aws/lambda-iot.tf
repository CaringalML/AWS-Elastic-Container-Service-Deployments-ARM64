# ==============================================================================
# Lambda — Kinesis → RDS IoT consumer
# ==============================================================================
# Runs inside the VPC (private subnets) so it can reach RDS directly.
# Triggered by Kinesis event source mapping (pull-based, not push).
# Reads DB credentials from Secrets Manager at cold-start and caches them.
# ==============================================================================

# ------------------------------------------------------------------------------
# Security Group for IoT Lambda
# No ingress needed — Kinesis ESM uses pull, not push.
# Egress: PostgreSQL to RDS SG + HTTPS for Secrets Manager / CloudWatch.
# ------------------------------------------------------------------------------
resource "aws_security_group" "lambda_iot" {
  name        = "${var.project_name}-lambda-iot-sg"
  description = "IoT Lambda - egress to RDS and AWS APIs only"
  vpc_id      = aws_vpc.main.id

  egress {
    description     = "PostgreSQL to RDS"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.db_sg.id]
  }

  egress {
    description = "HTTPS for Secrets Manager and CloudWatch Logs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-lambda-iot-sg" }
}

# Allow Lambda IoT SG inbound to RDS
resource "aws_security_group_rule" "db_from_lambda_iot" {
  type                     = "ingress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lambda_iot.id
  security_group_id        = aws_security_group.db_sg.id
  description              = "Allow IoT Lambda to access PostgreSQL"
}

# ------------------------------------------------------------------------------
# IAM Role for IoT Lambda
# ------------------------------------------------------------------------------
resource "aws_iam_role" "lambda_iot" {
  name = "${var.project_name}-lambda-iot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# VPC Access + CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_iot_vpc" {
  role       = aws_iam_role.lambda_iot.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Kinesis read + Secrets Manager
resource "aws_iam_policy" "lambda_iot_policy" {
  name        = "${var.project_name}-lambda-iot-policy"
  description = "Allow IoT Lambda to consume Kinesis and read DB credentials"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:ListStreams",
          "kinesis:ListShards",
        ]
        Resource = aws_kinesis_stream.iot.arn
      },
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.db_credentials.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_iot_policy" {
  role       = aws_iam_role.lambda_iot.name
  policy_arn = aws_iam_policy.lambda_iot_policy.arn
}

# ------------------------------------------------------------------------------
# Lambda Deployment Package
# Install pg8000 (pure Python — no binary compilation needed) before zipping.
# On first run / when requirements.txt changes, Terraform installs deps locally.
# ------------------------------------------------------------------------------
resource "null_resource" "install_iot_lambda_deps" {
  triggers = {
    requirements = filemd5("${path.module}/lambda-python/kinesis-to-rds/requirements.txt")
  }

  provisioner "local-exec" {
    command = "pip install -r ${path.module}/lambda-python/kinesis-to-rds/requirements.txt -t ${path.module}/lambda-python/kinesis-to-rds/ --quiet --upgrade"
  }
}

data "archive_file" "iot_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda-python/kinesis-to-rds/"
  output_path = "${path.module}/kinesis_to_rds.zip"

  depends_on = [null_resource.install_iot_lambda_deps]
}

# ------------------------------------------------------------------------------
# Lambda Function
# ------------------------------------------------------------------------------
resource "aws_lambda_function" "kinesis_to_rds" {
  function_name    = "${var.project_name}-kinesis-to-rds"
  role             = aws_iam_role.lambda_iot.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  architectures    = ["arm64"]
  filename         = data.archive_file.iot_lambda_zip.output_path
  source_code_hash = data.archive_file.iot_lambda_zip.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda_iot.id]
  }

  environment {
    variables = {
      DB_SECRET_ARN = aws_secretsmanager_secret.db_credentials.arn
      AWS_REGION_NAME = var.aws_region
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_iot_vpc,
    aws_iam_role_policy_attachment.lambda_iot_policy,
  ]
}

# CloudWatch log group for IoT Lambda
resource "aws_cloudwatch_log_group" "lambda_iot" {
  name              = "/aws/lambda/${aws_lambda_function.kinesis_to_rds.function_name}"
  retention_in_days = 7

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# ------------------------------------------------------------------------------
# Kinesis Event Source Mapping
# ------------------------------------------------------------------------------
resource "aws_lambda_event_source_mapping" "kinesis_to_rds" {
  event_source_arn  = aws_kinesis_stream.iot.arn
  function_name     = aws_lambda_function.kinesis_to_rds.arn
  starting_position = "LATEST"
  batch_size        = 10

  # Retry failed batches up to 2 times before discarding
  maximum_retry_attempts = 2
}
