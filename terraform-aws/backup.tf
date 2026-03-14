
resource "aws_backup_vault" "main" {
	count = var.enable_backup ? 1 : 0
	name  = "caringal-backup-vault"
}

resource "aws_backup_plan" "main" {
	count = var.enable_backup ? 1 : 0
	name  = "caringal-backup-plan"

	rule {
		rule_name         = "daily-backup"
		target_vault_name = aws_backup_vault.main[0].name
		schedule          = "cron(0 5 * * ? *)" # daily at 5am UTC
		lifecycle {
			delete_after = 30 # Retain backups for 30 days, then delete automatically
		}
	}
}

resource "aws_iam_role" "backup_role" {
	count = var.enable_backup ? 1 : 0
	name = "aws-backup-role"
	assume_role_policy = data.aws_iam_policy_document.backup_assume_role_policy[count.index].json
}

data "aws_iam_policy_document" "backup_assume_role_policy" {
	count = var.enable_backup ? 1 : 0
	statement {
		actions = ["sts:AssumeRole"]
		principals {
			type        = "Service"
			identifiers = ["backup.amazonaws.com"]
		}
	}
}

resource "aws_backup_selection" "rds" {
	count         = var.enable_backup ? 1 : 0
	name          = "rds-selection"
	iam_role_arn  = aws_iam_role.backup_role[0].arn
	plan_id       = aws_backup_plan.main[0].id

	resources = [
		aws_db_instance.db_instance.arn
	]
}

