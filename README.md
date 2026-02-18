# ECS Fargate + Self-Managed Instances - ARM64 (Graviton) Terraform

Terraform infrastructure for deploying a containerized application on AWS ECS with self-managed EC2 instances using ARM64/Graviton architecture.

## Architecture

```
Internet → ALB (public) → EC2 t4g.micro/t4g.small (Graviton3, ARM64)
                               ↑
                        ECS Task (bridge mode)
                        Provisioning: 1 On-Demand base + Spot for scale
```

You have **full control** over the EC2 instances — instance type, ASG min/max, scaling policies, and patching. Uses a **Mixed instances policy** to balance cost and stability.

## Provisioning Model - Mixed Instances

| Scenario | Instance | Cost/month (USD) |
|---|---|---|
| 1 instance (base) | On-Demand t4g.micro | ~$8.50 |
| Scale to 3 instances | 1 On-Demand + 2 Spot | ~$8.50 + ~$5.10 = ~$13.60 |
| Scale to 5 instances | 1 On-Demand + 4 Spot | ~$8.50 + ~$10.20 = ~$18.70 |

- **1 On-Demand base** — always running, never interrupted, stable foundation
- **All scale-up goes to Spot** — up to 70% cheaper than On-Demand
- **Fallback instance types** — `t4g.micro` primary, `t4g.small` if micro Spot unavailable
- **Strategy** — `price-capacity-optimized` for best balance of price + availability

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
| EC2 Instances | t4g.micro (primary) / t4g.small (fallback) |
| Architecture | Linux/ARM64 (Graviton3) |
| Network mode | bridge |
| vCPU | 0.25 |
| Memory | 0.5 GB |
| VPC | New VPC (10.0.0.0/16) |
| Subnets | 3 public subnets (ap-southeast-2a/b/c) |
| Task Public IP | ❌ None - EC2 SG blocks direct access |
| ALB | ✅ Required |
| ASG | ✅ You manage it |
| Provisioning | Mixed (On-Demand base + Spot scale) |

## Files

```
├── alb.tf                        # ALB, target group, listener, ASG attachment
├── cloudwatch.tf                 # CloudWatch log group
├── cluster.tf                    # ECS cluster, ASG (mixed policy), launch template, capacity provider
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
| `log_group_skip_destroy` | `true` | Preserve logs on terraform destroy |

## CI/CD

Docker image is built and pushed automatically via GitHub Actions using a native ARM64 runner:

```yaml
runs-on: ubuntu-24.04-arm  # Native ARM64 - no QEMU emulation
```

See `.github/workflows/build-arm64.yml` for the full pipeline.
