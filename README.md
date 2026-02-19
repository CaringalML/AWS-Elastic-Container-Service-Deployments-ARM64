# ECS Fargate + Self-Managed Instances - ARM64 (Graviton) Terraform

Terraform infrastructure for deploying a containerized application on AWS ECS with self-managed EC2 instances using ARM64/Graviton architecture.

## Architecture

```
Internet → ALB (public) → EC2 t4g.micro/t4g.small/t4g.medium (Graviton3, ARM64)
                               ↑
                        ECS Task (bridge mode)
                        Provisioning: 100% Pure Spot
```

You have **full control** over the EC2 instances — instance type, ASG min/max, scaling policies, and patching. Uses **Pure Spot** for maximum cost savings.

## Provisioning Model - Pure Spot

| Scenario | Instance | Cost/month (USD) |
|---|---|---|
| 1 instance | Spot t4g.micro | ~$2.55 |
| Scale to 3 instances | 3x Spot | ~$7.65 |
| Scale to 5 instances | 5x Spot | ~$12.75 |

- **100% Spot** — zero On-Demand, maximum cost savings (up to 70% cheaper)
- **3 fallback instance types** — `t4g.micro` → `t4g.small` → `t4g.medium` for better Spot availability
- **Strategy** — `price-capacity-optimized` for best balance of price + availability
- **⚠️ Trade-off** — Spot instances can be interrupted by AWS with 2 minutes notice

## Scaling Triggers

Two policies run simultaneously — whichever fires first wins:

| Trigger | Condition | Action |
|---|---|---|
| Task demand | Pending tasks > available capacity | Scale out (1-5 instances) |
| CPU | Average CPU > 70% | Scale out to bring CPU back to 70% |
| Scale-in | Both CPU low + tasks have capacity | Drain tasks → terminate instance |

**Cooldown & warmup settings:**
- `instance_warmup_period = 60s` — time before new instance is included in scaling metrics
- `managed_draining = ENABLED` — ECS drains tasks off instance before termination
- `managed_termination_protection = ENABLED` — prevents ASG from killing instances with running tasks

## Fargate vs Managed vs Self-Managed

| | Fargate | Fargate + Managed | Fargate + Self-Managed |
|---|---|---|---|
| EC2 under the hood | ❌ | ✅ AWS picks instance | ✅ You pick instance |
| Network mode | awsvpc | awsvpc | bridge |
| ALB required | ❌ | ✅ | ✅ |
| Target type | ip | ip | instance |
| You manage patching | ❌ | ❌ | ✅ |
| You manage ASG | ❌ | ❌ | ✅ |
| Spot support | ✅ FARGATE_SPOT | ❌ | ✅ Full control |
| Cost | Highest | Lower | Lowest |

## Infrastructure Overview

| Resource | Details |
|---|---|
| ECS Cluster | Fargate + Self-managed |
| EC2 Instances | t4g.micro → t4g.small → t4g.medium (Spot fallback chain) |
| Architecture | Linux/ARM64 (Graviton3) |
| Network mode | bridge |
| vCPU | 0.25 |
| Memory | 0.5 GB |
| VPC | New VPC (10.0.0.0/16) |
| Subnets | 3 public subnets (ap-southeast-2a/b/c) |
| Task Public IP | ❌ None - EC2 SG only allows ALB traffic |
| ALB | ✅ Required |
| ASG | ✅ You manage it |
| Provisioning | Pure Spot (100%) |

## Files

```
├── alb.tf                        # ALB, target group (instance type), listener, ASG attachment
├── cloudwatch.tf                 # CloudWatch log group
├── cluster.tf                    # ECS cluster, ASG (pure spot), launch template, capacity provider
├── ecs-self-managed-service.tf   # ECS service only
├── iam.tf                        # Task execution role, task role, instance role
├── outputs.tf                    # Output values after apply
├── security-group.tf             # ALB SG (public) + EC2 instances SG (ALB only)
├── task-definition.tf            # ARM64 container definition (bridge mode)
├── variables.tf                  # All configurable variables
├── versions.tf                   # Terraform and provider versions
└── vpc.tf                        # VPC, subnets, IGW, route tables
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

After apply, the ALB DNS name is printed as output:
```
alb_dns_name = "http://hello-world-arm64-xxxxxx.ap-southeast-2.elb.amazonaws.com"
```

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
| `host_port` | `80` | EC2 host port mapped to container |
| `task_cpu` | `256` | CPU units (256 = 0.25 vCPU) |
| `task_memory` | `512` | Memory in MB |
| `asg_min_size` | `1` | ASG minimum instances |
| `asg_max_size` | `5` | ASG maximum instances |
| `asg_desired_capacity` | `1` | ASG desired instances |
| `log_group_skip_destroy` | `false` | Delete logs on terraform destroy |

## CI/CD

The Docker image is built and pushed automatically via GitHub Actions on every push or pull request to `main`. The workflow uses a **native ARM64 GitHub-hosted runner** (`ubuntu-24.04-arm`) — no QEMU emulation, no cross-compilation overhead.

`.github/workflows/build-arm64.yml`:

```yaml
name: Build ARM64 and Push to Docker Hub

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

jobs:
  build-and-push:
    runs-on: ubuntu-24.04-arm  # Native ARM64 GitHub-hosted runner

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build and Push ARM64 image
        run: |
          docker build -t rencecaringal000/helloworldarm64:latest .
          docker push rencecaringal000/helloworldarm64:latest
```

### Required GitHub Secrets

Add these secrets to your repository under **Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Your Docker Hub password |