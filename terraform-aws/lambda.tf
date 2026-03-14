# archive_file zips the Lambda source at plan time — no shell dependency needed
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda-python/auto-update-task-definition.py"
  output_path = "${path.module}/update_ecs_taskdef.zip"
}

resource "aws_lambda_function" "ecs_taskdef_update" {
  function_name    = "update-ecs-taskdef-on-ecr-push"
  role             = aws_iam_role.lambda_ecs_update.arn
  handler          = "auto-update-task-definition.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      CLUSTER        = aws_ecs_cluster.main.name
      SERVICE        = aws_ecs_service.main.name
      TASK_FAMILY    = aws_ecs_task_definition.main.family
      CONTAINER_NAME = var.project_name
      ECS_REGION     = var.aws_region
    }
  }
}

resource "aws_iam_role" "lambda_ecs_update" {
  name = "lambda-ecs-update-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ecs_update_policy" {
  role       = aws_iam_role.lambda_ecs_update.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "ecs_update_taskdef" {
  name        = "ecs-update-taskdef-policy"
  description = "Allow Lambda to update ECS service task definition"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
        ]
        Resource = "*"
      },
      {
        # RegisterTaskDefinition requires PassRole on both the task role and
        # execution role that are embedded in the task definition being registered.
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [
          aws_iam_role.ecs_task_role.arn,
          aws_iam_role.ecs_task_execution_role.arn,
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ecs_update_ecs_policy" {
  role       = aws_iam_role.lambda_ecs_update.name
  policy_arn = aws_iam_policy.ecs_update_taskdef.arn
}
