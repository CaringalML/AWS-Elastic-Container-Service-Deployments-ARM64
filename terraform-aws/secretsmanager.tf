resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}-db-credentials"
  description = "Database credentials for ${var.project_name}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id     = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.db_instance.address
    port     = var.db_port
    dbname   = var.db_database
  })
}

resource "aws_secretsmanager_secret_rotation" "db_credentials_rotation" {
  secret_id           = aws_secretsmanager_secret.db_credentials.id
  rotation_lambda_arn = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:SecretsManagerRDSPostgreSQLRotationSingleUser"
  rotation_rules {
    automatically_after_days = 30
  }
  depends_on = [aws_secretsmanager_secret_version.db_credentials_version]
}

data "aws_caller_identity" "current" {}

# Note: You must provide a Lambda function for rotation (var.db_rotation_lambda_arn) or set up AWS provided rotation templates for RDS/Postgres.

# ==============================================================================
# App-level secrets (Laravel APP_KEY, etc.)
# Set the value via: aws secretsmanager put-secret-value --secret-id <name> --secret-string '{"app_key":"base64:..."}'
# Or pass var.app_key via TF_VAR_app_key environment variable during terraform apply.
# ==============================================================================
resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "${var.project_name}-app-secrets"
  description             = "Laravel application secrets for ${var.project_name}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app_secrets_version" {
  secret_id     = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    app_key = var.app_key
  })
}
