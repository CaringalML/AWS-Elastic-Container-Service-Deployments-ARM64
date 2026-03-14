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
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# CloudFront ACM certificates must be issued in us-east-1 — this alias
# is used only in cloudfront.tf for the cdn.<domain> certificate.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
