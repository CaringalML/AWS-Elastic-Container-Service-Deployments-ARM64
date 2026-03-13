# ==============================================================================
# VPC - Network Foundation
# ==============================================================================
# Creates the core network layer:
#   - A VPC with DNS resolution enabled (required for ECS agent & ECR pulls)
#   - An Internet Gateway for outbound internet access
#   - 3 public subnets spread across AZs for high availability
#   - A single route table that routes all egress traffic through the IGW
#
# NOTE: All resources (ALB, EC2, ECS tasks) currently live in public subnets.
# EC2 instances have public IPs for SSM/outbound access; ECS tasks do NOT
# (assign_public_ip = false in ecs-self-managed-service.tf).
# ==============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true  # Required for ECS agent to resolve AWS endpoints
  enable_dns_hostnames = true  # Required for ECR image pulls via DNS

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Provides outbound internet access for EC2 instances and ECS tasks
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# One public subnet per availability zone.
# count.index maps each subnet to the corresponding AZ and CIDR from variables.
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true # EC2 instances get public IPs for SSM access

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
  }
}

# Single route table shared by all public subnets.
# Default route (0.0.0.0/0) sends all non-local traffic to the IGW.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Associate each public subnet with the shared route table
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
