# ==============================================================================
# VERSIONS - Terraform & Provider Requirements
# ==============================================================================
# Pins the minimum Terraform CLI version and the AWS provider version range.
# The lock file (.terraform.lock.hcl) records the exact provider version
# selected during `terraform init` — commit it to source control so all
# team members and CI pipelines use identical provider binaries.
# ==============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Allows 5.x patch/minor updates, blocks 6.x breaking changes
    }
  }
}

provider "aws" {
  region = var.aws_region
}
