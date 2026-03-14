resource "aws_cloudwatch_event_rule" "ecr_image_push" {
  name        = "ecr-image-push-rule"
  description = "Trigger Lambda on ECR image push"
  event_pattern = jsonencode({
    source      = ["aws.ecr"],
    detail-type = ["ECR Image Action"],
    detail      = {
      "action-type" = ["PUSH"]
      "repository-name" = [aws_ecr_repository.employee_crud.name]
    }
  })
}

resource "aws_cloudwatch_event_target" "ecr_push_lambda" {
  rule      = aws_cloudwatch_event_rule.ecr_image_push.name
  target_id = "ecs-taskdef-update-lambda"
  arn       = aws_lambda_function.ecs_taskdef_update.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecs_taskdef_update.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecr_image_push.arn
}
