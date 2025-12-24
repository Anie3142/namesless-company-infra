# Nameless Company Infrastructure

Production-ready AWS infrastructure for running n8n workflow automation on ECS Fargate Spot.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Cloudflare                                │
│                    (DNS + SSL + CDN)                            │
└──────────────────────────┬──────────────────────────────────────┘
                           │ HTTPS
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                         AWS VPC                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    Public Subnets                          │  │
│  │  ┌─────────────┐     ┌─────────────────────────────────┐  │  │
│  │  │    NAT      │     │     Application Load Balancer   │  │  │
│  │  │  Instance   │     │          (ALB)                  │  │  │
│  │  │  (t3.micro) │     └─────────────────────────────────┘  │  │
│  │  └─────────────┘                    │                      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                               │                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    Private Subnets                         │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │              ECS Fargate Spot                        │  │  │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐              │  │  │
│  │  │  │  n8n    │  │  Future │  │  Future │              │  │  │
│  │  │  │  Task   │  │   App   │  │   App   │              │  │  │
│  │  │  └─────────┘  └─────────┘  └─────────┘              │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Cost Estimate

| Resource | Monthly Cost |
|----------|--------------|
| NAT Instance (t3.micro) | ~$8.50 |
| ALB | ~$16 |
| ECS Fargate Spot (n8n) | ~$3-5 |
| CloudWatch Logs | ~$0.50 |
| **Total** | **~$28-30/month** |

## Directory Structure

```
infra/
├── modules/              # Reusable Terraform modules
│   ├── networking/       # VPC, subnets, route tables
│   ├── nat-instance/     # NAT instance for private subnet egress
│   ├── alb/              # Application Load Balancer
│   ├── ecs-cluster/      # ECS cluster with Fargate Spot
│   ├── ecs-service/      # Generic ECS service module
│   ├── ecr/              # ECR repository
│   └── iam/              # IAM roles
│       ├── ecs-task-execution/
│       └── ecs-task-role/
│
├── live/                 # Live infrastructure stacks
│   ├── 00-state/         # Terraform state backend (S3 + DynamoDB)
│   ├── 10-network/       # VPC, subnets, NAT instance
│   ├── 20-ecs/           # ECS cluster, ALB, ECR, IAM
│   └── 30-apps/
│       └── n8n/          # n8n application
│
└── scripts/
    ├── deploy.sh         # Deploy all infrastructure
    └── destroy.sh        # Destroy all infrastructure
```

## Quick Start

### Prerequisites

1. **AWS CLI** with configured credentials
2. **Terraform** >= 1.0
3. **AWS SSO Login** (if using SSO):
   ```bash
   aws sso login --profile your-profile
   export AWS_PROFILE=your-profile
   ```

### Deploy Everything

```bash
cd infra/scripts
./deploy.sh
```

This will deploy stacks in order:
1. `00-state` - Terraform backend
2. `10-network` - VPC, subnets, NAT
3. `20-ecs` - ECS cluster, ALB, ECR
4. `30-apps/n8n` - n8n application

### Get ALB DNS for Cloudflare

After deployment, get the ALB DNS:

```bash
cd infra/live/20-ecs
terraform output alb_dns_name
```

### Configure Cloudflare

1. Add a **CNAME** record:
   - **Name**: `n8n` (or your subdomain)
   - **Target**: ALB DNS name from above
   - **Proxy**: Enabled (orange cloud)

2. Set SSL mode to **Full** or **Full (strict)**

3. Enable **Always Use HTTPS**

### Destroy Everything

```bash
cd infra/scripts
./destroy.sh
```

## Manual Stack Deployment

If you prefer deploying stacks individually:

```bash
# 1. State backend
cd infra/live/00-state
terraform init
terraform apply

# 2. Network
cd ../10-network
terraform init
terraform apply

# 3. ECS platform
cd ../20-ecs
terraform init
terraform apply

# 4. n8n application
cd ../30-apps/n8n
terraform init
terraform apply
```

## Configuration

### Customize n8n

Edit `infra/live/30-apps/n8n/variables.tf` or create a `terraform.tfvars`:

```hcl
# terraform.tfvars
n8n_host_header    = "n8n.yourdomain.com"
n8n_webhook_url    = "https://n8n.yourdomain.com/webhook"
n8n_encryption_key = "your-secure-encryption-key"
n8n_cpu            = 512
n8n_memory         = 1024
```

### Customize Network

Edit `infra/live/10-network/variables.tf`:

```hcl
vpc_cidr        = "10.0.0.0/16"
public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]
```

## Monitoring

### View n8n Logs

```bash
aws logs tail /ecs/nameless-n8n --follow
```

### Check ECS Service Status

```bash
aws ecs describe-services \
  --cluster nameless-cluster \
  --services nameless-n8n
```

## Troubleshooting

### n8n Task Not Starting

1. Check CloudWatch logs:
   ```bash
   aws logs tail /ecs/nameless-n8n --follow
   ```

2. Check target group health:
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn $(terraform output -raw target_group_arn)
   ```

### No Internet Access from Tasks

1. Verify NAT instance is running:
   ```bash
   aws ec2 describe-instances --filters "Name=tag:Name,Values=nameless-nat"
   ```

2. Check route tables point to NAT instance

### ALB Not Responding

1. Check security groups allow traffic
2. Verify listener rules are correct
3. Check target group has healthy targets

## Future Enhancements

- [ ] Add RDS PostgreSQL for n8n persistence
- [ ] Add Redis for n8n queue mode
- [ ] Enable HTTPS listener with ACM certificate
- [ ] Add auto-scaling based on CPU/memory
- [ ] Add CloudWatch alarms and dashboards
