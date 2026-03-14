variable "db_rotation_lambda_arn" {
  description = "ARN of the Lambda function for Secrets Manager rotation (required for automatic rotation)"
  type        = string
  default     = ""
}

######################################################################
# General App/Infra Variables
######################################################################

# Docker image variable for ECS
variable "docker_image" {
  description = "Docker image URI for ECS deployment"
  type        = string
}

# Database variables for RDS
variable "db_database" {
  description = "Database name for RDS"
  type        = string
}
variable "db_username" {
  description = "Database username for RDS"
  type        = string
}
variable "db_password" {
  description = "Database password for RDS"
  type        = string
}
variable "db_port" {
  description = "Database port for RDS"
  type        = number
  default     = 5432
}

# Subnet and region
variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

######################################################################
# New Features: Domain, DNS, Secrets, Env, Backup
######################################################################

# Root domain name for Route53/ACM
variable "domain_name" {
  description = "The root domain name (e.g. nodepulsecaringal.xyz)"
  type        = string
  default     = "nodepulsecaringal.xyz"
}


# Environment (dev, staging, prod) for tagging and config
variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Project name for tagging and resource naming
variable "project_name" {
  description = "Project name for tagging AWS resources"
  type        = string
  default     = "webapp"
}

# Enable/disable AWS Backup resources
variable "enable_backup" {
  description = "Enable AWS Backup resources (set to true for prod, false for dev)"
  type        = bool
  default     = false
}

# Skip final snapshot on DB deletion (true for dev, false for prod)
variable "skip_final_snapshot" {
  description = "Skip final snapshot on DB deletion (true for dev, false for prod)"
  type        = bool
  default     = true
}


variable "container_port" {
  description = "Port the container listens on (exposed directly in awsvpc mode)"
  type        = number
  default     = 80
}

# NOTE: var.host_port was removed as it is not used in awsvpc mode.

variable "task_cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Task memory in MB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to run"
  type        = number
  default     = 1
}

variable "asg_min_size" {
  description = "Minimum number of EC2 instances in ASG"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of EC2 instances in ASG"
  type        = number
  default     = 5
}

variable "asg_desired_capacity" {
  description = "Desired number of EC2 instances in ASG"
  type        = number
  default     = 1
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["ap-southeast-2a", "ap-southeast-2b"]
}

variable "log_group_skip_destroy" {
  description = "If true, CloudWatch log group will NOT be deleted on terraform destroy"
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications via SNS"
  type        = string
  default     = "lawrencecaringal5@gmail.com"
}

######################################################################
# Laravel Application Variables
######################################################################

variable "app_key" {
  description = "Laravel APP_KEY. Generate with: php artisan key:generate --show"
  type        = string
  sensitive   = true
}

variable "app_env" {
  description = "Laravel APP_ENV (local | staging | production)"
  type        = string
  default     = "production"
}

variable "app_debug" {
  description = "Laravel APP_DEBUG — must be false in production"
  type        = bool
  default     = false
}

variable "log_level" {
  description = "Laravel LOG_LEVEL (debug | info | warning | error)"
  type        = string
  default     = "error"
}