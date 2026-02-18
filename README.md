# ECS Fargate - ARM64 (Graviton) Terraform

Terraform infrastructure for deploying a containerized application on AWS ECS Fargate with ARM64/Graviton architecture.

## Architecture

```
Internet → Task Public IP:80 → nginx container (ARM64)
```

Since ECS Fargate is **serverless**, tasks can be assigned a public IP directly — no ALB required. This keeps the setup simple and cost-effective for dev/test environments.

> **Note:** For production, consider adding an ALB for a stable DNS endpoint, SSL termination, and protection against direct task exposure.

## Infrastructure Overview

| Resource | Details |
|---|---|
| ECS Cluster | Fargate (serverless) |
| Architecture | Linux/ARM64 (Graviton) |
| Network mode | awsvpc |
| vCPU | 0.25 |
| Memory | 0.5 GB |
| VPC | New VPC (10.0.0.0/16) |
| Subnets | 3 public subnets (ap-southeast-2a/b/c) |
| Public IP | Assigned directly to task |
| ALB | ❌ Not needed (serverless = direct public IP) |

## Files

```
├── cloudwatch.tf         # CloudWatch log group for container logs
├── cluster.tf            # ECS cluster with Fargate capacity provider
├── ecs-fargate-service.tf # ECS service with network config
├── iam.tf                # Task execution role and task role
├── outputs.tf            # Output values after apply
├── security-group.tf     # Security group allowing HTTP on port 80
├── task-definition.tf    # ARM64 container definition
├── variables.tf          # All configurable variables
├── versions.tf           # Terraform and provider versions
└── vpc.tf                # VPC, subnets, IGW, route tables
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- AWS CLI configured with credentials
- Docker image pushed to Docker Hub (`rencecaringal000/helloworldarm64:latest`)

## Usage

### Deploy

```bash
terraform init
terraform plan
terraform apply
```

### Access the app

After apply, go to:
```
ECS → Cluster → Tasks → click task → copy Public IP
```
Then open `http://<public-ip>` in your browser.

### Destroy

```bash
# Keep CloudWatch logs (default)
terraform destroy

# Delete CloudWatch logs as well
terraform destroy -var="log_group_skip_destroy=false"
```

> After destroy, manually delete the `/aws/ecs/containerinsights/hello-world-arm64/performance` log group from CloudWatch console — it is auto-created by Container Insights and not managed by Terraform.

## Variables

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `ap-southeast-2` | AWS region |
| `project_name` | `hello-world-arm64` | Name prefix for all resources |
| `container_image` | `rencecaringal000/helloworldarm64:latest` | Docker Hub image |
| `container_port` | `80` | Container port |
| `task_cpu` | `256` | CPU units (256 = 0.25 vCPU) |
| `task_memory` | `512` | Memory in MB (512 = 0.5 GB) |
| `desired_count` | `1` | Number of tasks to run |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `log_group_skip_destroy` | `true` | Preserve logs on terraform destroy |

## CI/CD

Docker image is built and pushed automatically via GitHub Actions using a native ARM64 runner:

```yaml
runs-on: ubuntu-24.04-arm  # Native ARM64 - no QEMU emulation
```

See `.github/workflows/build-arm64.yml` for the full pipeline.
