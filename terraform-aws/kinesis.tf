# ==============================================================================
# Kinesis Data Stream — IoT Events from M5Stack devices
# ==============================================================================
# Single shard is sufficient for low-throughput IoT data.
# 24-hour retention covers any Lambda processing delays.
# ==============================================================================

resource "aws_kinesis_stream" "iot" {
  name             = "${var.project_name}-iot-events"
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Name        = "${var.project_name}-iot-events"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ==============================================================================
# IAM User — M5Stack hardware device
# ==============================================================================
# Least-privilege: only PutRecord on this specific stream.
# Create an access key for this user in the AWS Console after apply,
# then copy the credentials into the Arduino sketch.
# ==============================================================================

resource "aws_iam_user" "m5stack" {
  name = "${var.project_name}-m5stack-device"

  tags = {
    Name        = "${var.project_name}-m5stack-device"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_policy" "kinesis_put" {
  name        = "${var.project_name}-kinesis-put-policy"
  description = "Allow M5Stack device to put records into the IoT Kinesis stream"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kinesis:PutRecord", "kinesis:PutRecords"]
      Resource = aws_kinesis_stream.iot.arn
    }]
  })
}

resource "aws_iam_user_policy_attachment" "m5stack_kinesis" {
  user       = aws_iam_user.m5stack.name
  policy_arn = aws_iam_policy.kinesis_put.arn
}

# ==============================================================================
# Outputs
# ==============================================================================

output "kinesis_stream_name" {
  description = "Kinesis stream name (use in M5Stack sketch and Lambda env)"
  value       = aws_kinesis_stream.iot.name
}

output "kinesis_stream_arn" {
  description = "Kinesis stream ARN"
  value       = aws_kinesis_stream.iot.arn
}

output "m5stack_iam_user" {
  description = "IAM user for M5Stack — create an access key in the AWS Console"
  value       = aws_iam_user.m5stack.name
}
