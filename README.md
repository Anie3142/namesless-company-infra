# Nameless Company Infrastructure

Production-ready AWS infrastructure for running n8n workflow automation on **ECS Fargate Spot**.

## 🎯 Quick Start

```bash
# 1. Login to AWS
aws sso login --profile your-profile
export AWS_PROFILE=your-profile

# 2. Deploy everything
cd infra/scripts
./deploy.sh

# 3. Get ALB DNS for Cloudflare
cd ../live/20-ecs
terraform output alb_dns_name
```

## 📁 Project Structure

```
.
├── infra/                    # 🏗️ Main infrastructure (ECS-based)
│   ├── live/                 # Live stacks (deploy these)
│   │   ├── 00-state/         # Terraform backend (S3 + DynamoDB)
│   │   ├── 10-network/       # VPC, subnets, NAT instance
│   │   ├── 20-ecs/           # ECS cluster, ALB, ECR, IAM
│   │   └── 30-apps/n8n/      # n8n application
│   ├── modules/              # Reusable Terraform modules
│   ├── scripts/              # Deploy/destroy scripts
│   └── README.md             # Detailed infrastructure docs
│
├── docs/                     # 📚 Documentation
│   ├── aws-sso-setup.md      # AWS SSO configuration guide
│   ├── INFRASTRUCTURE_MASTER_PLAN.md
│   ├── LOAD_BALANCER_COMPARISON.md
│   └── SPOT_CAPACITY_CRISIS.md
│
├── scripts/                  # 🔧 Helper scripts
│   ├── cleanup-s3-buckets.sh # S3 cleanup utility
│   ├── deploy-with-sso.sh    # SSO-aware deployment
│   ├── get-sso-creds.py      # SSO credential helper
│   └── terraform-with-sso.sh # SSO Terraform wrapper
│
└── _archive/                 # 📦 Old kOps/K8s setup (gitignored)
```

## 💰 Cost Estimate

| Resource | Monthly Cost |
|----------|--------------|
| NAT Instance (t3.micro) | ~$8.50 |
| Application Load Balancer | ~$16 |
| ECS Fargate Spot (n8n) | ~$3-5 |
| CloudWatch Logs | ~$0.50 |
| **Total** | **~$28-30/month** |

## 🚀 Deployment Guide

See [`infra/README.md`](./infra/README.md) for detailed deployment instructions.

### TL;DR

1. Configure AWS credentials (SSO or access keys)
2. Run `./infra/scripts/deploy.sh`
3. Add ALB DNS as CNAME in Cloudflare
4. Access n8n at `https://your-domain.com`

## 🌐 Cloudflare Setup

After deployment:

1. **DNS Settings**
   - Type: `CNAME`
   - Name: `n8n` (or your subdomain)
   - Target: ALB DNS from terraform output
   - Proxy: Enabled (orange cloud)

2. **SSL/TLS Settings**
   - Mode: `Full` or `Full (strict)`
   - Enable "Always Use HTTPS"

## 🔧 Configuration

Create `infra/live/30-apps/n8n/terraform.tfvars`:

```hcl
n8n_host_header    = "n8n.yourdomain.com"
n8n_webhook_url    = "https://n8n.yourdomain.com/webhook"
n8n_encryption_key = "your-secure-encryption-key"
```

## 📊 Monitoring

```bash
# View n8n logs
aws logs tail /ecs/nameless-n8n --follow

# Check ECS service
aws ecs describe-services --cluster nameless-cluster --services nameless-n8n
```

## 🗑️ Teardown

```bash
cd infra/scripts
./destroy.sh
```

## 📖 Documentation

- [Infrastructure Details](./infra/README.md)
- [AWS SSO Setup](./docs/aws-sso-setup.md)
- [Master Plan](./docs/INFRASTRUCTURE_MASTER_PLAN.md)

## 🏛️ Architecture

```
                    ┌─────────────┐
                    │ Cloudflare  │
                    │ (DNS + SSL) │
                    └──────┬──────┘
                           │ HTTPS
                           ▼
┌──────────────────────────────────────────────────────────────┐
│                        AWS VPC                                │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                  Public Subnets                         │  │
│  │  ┌───────────┐       ┌───────────────────────────────┐ │  │
│  │  │    NAT    │       │            ALB                │ │  │
│  │  │ Instance  │       │   (Application Load Balancer) │ │  │
│  │  └───────────┘       └───────────────────────────────┘ │  │
│  └────────────────────────────────────────────────────────┘  │
│                              │                                │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                 Private Subnets                         │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │             ECS Fargate Spot                      │  │  │
│  │  │  ┌─────────────┐                                  │  │  │
│  │  │  │    n8n      │                                  │  │  │
│  │  │  │   Service   │                                  │  │  │
│  │  │  └─────────────┘                                  │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

## License

MIT
