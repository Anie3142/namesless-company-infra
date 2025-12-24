# 🏗️ Nameless Company Infrastructure Master Plan

> **Last Updated**: December 2024  
> **Status**: Phase 1 - ECS Foundation  
> **Owner**: Personal Infrastructure Project

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture Decisions](#2-architecture-decisions)
3. [Folder Structure](#3-folder-structure)
4. [Terraform Modules](#4-terraform-modules)
5. [Live Stacks](#5-live-stacks)
6. [Current Implementation (Phase 1)](#6-current-implementation-phase-1)
7. [Future Expansions](#7-future-expansions)
8. [Cost Analysis](#8-cost-analysis)
9. [Security Considerations](#9-security-considerations)
10. [Operational Runbooks](#10-operational-runbooks)
11. [Content Creation Notes](#11-content-creation-notes)

---

## 1. Project Overview

### 1.1 Goals & Objectives

| Goal | Description | Priority |
|------|-------------|----------|
| **Personal Infrastructure** | Host personal applications (n8n, tax-api, finance-api, RAG apps) | High |
| **Kubernetes Certifications** | CKA/CKAD preparation with real infrastructure | High |
| **DevOps Learning** | Hands-on experience with Terraform, ECS, CI/CD | High |
| **Content Creation** | YouTube videos and blog posts about infrastructure | Medium |
| **Cost Efficiency** | Keep monthly costs under $50 | High |
| **Job Relevance** | Skills that apply to current job (ECS) and future jobs (K8s) | High |

### 1.2 Key Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Always-on Platform** | AWS ECS | Cheaper, job-relevant, low maintenance |
| **Learning Platform** | Kubernetes (local + burst) | CKA/CKAD prep, industry standard |
| **NAT Solution** | NAT Instance (t3.micro) | ~$5/month vs $32/month NAT Gateway |
| **Compute** | Fargate Spot | 70% cheaper than on-demand |
| **IaC Tool** | Terraform | Industry standard, modular, portable |
| **State Management** | S3 + DynamoDB | Best practice for team/CI collaboration |
| **DNS/CDN** | Cloudflare | Free tier, DDoS protection, SSL |
| **Observability** | CloudWatch (now) → Grafana (later) | Start simple, expand when needed |

### 1.3 Cost Targets

| Phase | Monthly Target | Actual |
|-------|---------------|--------|
| Phase 1 (ECS + n8n) | < $40 | TBD |
| Phase 2 (+ more apps) | < $60 | TBD |
| Phase 3 (+ K8s burst) | < $80 | TBD |

---

## 2. Architecture Decisions

### 2.1 Why ECS Over Kubernetes for Production?

**For Always-On Applications:**

| Factor | ECS | Kubernetes |
|--------|-----|------------|
| **Control Plane Cost** | $0 | ~$73/month (EKS) or 1+ EC2 (kOps) |
| **Minimum Viable Setup** | 1 Fargate task | 1 master + 1 worker minimum |
| **Operational Overhead** | Low (AWS managed) | High (you manage cluster) |
| **Learning Value** | Job-relevant | CKA/CKAD relevant |
| **Best For** | Simple services, cost-sensitive | Complex microservices, learning |

**Decision**: Use ECS for production apps, Kubernetes for learning.

### 2.2 Why Keep Kubernetes for Learning?

1. **CKA/CKAD certifications already paid for** - need hands-on practice
2. **Industry relevance** - most companies use Kubernetes
3. **Future job prospects** - K8s skills are in demand
4. **Content creation** - Kubernetes content is popular

**Strategy**:
- **Daily practice**: Local kind/k3d cluster (FREE)
- **Weekend sessions**: AWS kOps cluster (spin up → practice → tear down)
- **Estimated cost**: ~$10-20/month for burst usage

### 2.3 Why NAT Instance Over NAT Gateway?

| Factor | NAT Instance (t3.micro) | NAT Gateway |
|--------|-------------------------|-------------|
| **Monthly Cost** | ~$3-5 | ~$32+ |
| **Data Processing** | $0 | $0.045/GB |
| **Availability** | Single AZ (acceptable for personal) | Multi-AZ |
| **Bandwidth** | Limited (~100Mbps) | High (up to 100Gbps) |
| **Maintenance** | Manual (security patches) | Managed |

**Decision**: NAT Instance for cost savings. Acceptable risk for personal project.

**Mitigation**: Use userdata script for automatic security updates.

### 2.4 Why Fargate Spot?

| Factor | Fargate Spot | Fargate On-Demand | EC2 |
|--------|--------------|-------------------|-----|
| **Cost** | ~70% cheaper | Baseline | Depends on instance |
| **Availability** | Can be interrupted | Always available | Always available |
| **Management** | Zero (serverless) | Zero (serverless) | You manage EC2 |
| **Best For** | Stateless, fault-tolerant | Critical workloads | High customization |

**Decision**: Use Fargate Spot for n8n and stateless apps. Acceptable to have brief interruptions.

**Note**: For stateful apps (databases), use RDS or EBS-backed EC2.

### 2.5 Networking Design Rationale

```
┌─────────────────────────────────────────────────────────────────┐
│                         VPC: 10.0.0.0/16                        │
│                                                                 │
│  ┌─────────────────────────┐    ┌─────────────────────────┐    │
│  │   Public Subnet A        │    │   Public Subnet B        │    │
│  │   10.0.1.0/24            │    │   10.0.2.0/24            │    │
│  │   AZ: eu-central-1a      │    │   AZ: eu-central-1b      │    │
│  │                          │    │                          │    │
│  │   • NAT Instance         │    │   • (empty for now)      │    │
│  │   • ALB (multi-AZ)       │    │   • ALB (multi-AZ)       │    │
│  └─────────────────────────┘    └─────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────┐    ┌─────────────────────────┐    │
│  │   Private Subnet A       │    │   Private Subnet B       │    │
│  │   10.0.10.0/24           │    │   10.0.11.0/24           │    │
│  │   AZ: eu-central-1a      │    │   AZ: eu-central-1b      │    │
│  │                          │    │                          │    │
│  │   • ECS Tasks (Fargate)  │    │   • ECS Tasks (Fargate)  │    │
│  │   • Future: RDS          │    │   • Future: RDS          │    │
│  └─────────────────────────┘    └─────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ Internet Gateway │
                    └─────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   Cloudflare    │
                    │   (DNS + CDN)   │
                    └─────────────────┘
```

**Design Decisions**:
- **2 AZs** - Multi-AZ for ALB health (required), good practice
- **Public + Private subnets** - Best practice (public for LB, private for apps)
- **Single NAT Instance** - Cost optimization (not HA, acceptable for personal)
- **CIDR /16** - Room for expansion (65,536 IPs)

---

## 3. Folder Structure

### 3.1 Complete Structure

```
nameless-company-infra/
│
├─ README.md                              # Project overview
├─ .gitignore                             # Git ignore rules
│
├─ docs/                                  # Documentation
│  ├─ INFRASTRUCTURE_MASTER_PLAN.md       # This file
│  ├─ architecture.md                     # Architecture diagrams
│  └─ runbooks/                           # Operational guides
│     ├─ deploy-new-app.md
│     ├─ troubleshooting.md
│     └─ disaster-recovery.md
│
├─ infra/                                 # All infrastructure code
│  │
│  ├─ modules/                            # Reusable Terraform modules
│  │  ├─ networking/                      # VPC, subnets, routing
│  │  │  ├─ main.tf
│  │  │  ├─ variables.tf
│  │  │  ├─ outputs.tf
│  │  │  └─ README.md
│  │  │
│  │  ├─ nat-instance/                    # NAT instance (cost-effective)
│  │  │  ├─ main.tf
│  │  │  ├─ variables.tf
│  │  │  ├─ outputs.tf
│  │  │  └─ templates/
│  │  │     └─ userdata.sh
│  │  │
│  │  ├─ alb/                             # Application Load Balancer
│  │  │  ├─ main.tf
│  │  │  ├─ variables.tf
│  │  │  └─ outputs.tf
│  │  │
│  │  ├─ ecs-cluster/                     # ECS cluster
│  │  │  ├─ main.tf
│  │  │  ├─ variables.tf
│  │  │  └─ outputs.tf
│  │  │
│  │  ├─ ecs-service/                     # Generic ECS service
│  │  │  ├─ main.tf
│  │  │  ├─ variables.tf
│  │  │  └─ outputs.tf
│  │  │
│  │  ├─ ecr/                             # Container registry
│  │  │  ├─ main.tf
│  │  │  ├─ variables.tf
│  │  │  └─ outputs.tf
│  │  │
│  │  └─ iam/                             # IAM roles and policies
│  │     ├─ ecs-task-execution/
│  │     └─ ecs-task-role/
│  │
│  ├─ live/                               # Actual deployments (state lives here)
│  │  │
│  │  ├─ 00-state/                        # Terraform state backend
│  │  │  ├─ main.tf
│  │  │  ├─ variables.tf
│  │  │  └─ outputs.tf
│  │  │
│  │  ├─ 10-network/                      # Network infrastructure
│  │  │  ├─ main.tf
│  │  │  ├─ variables.tf
│  │  │  ├─ outputs.tf
│  │  │  ├─ backend.tf
│  │  │  └─ terraform.tfvars
│  │  │
│  │  ├─ 20-ecs/                          # ECS platform
│  │  │  ├─ main.tf
│  │  │  ├─ variables.tf
│  │  │  ├─ outputs.tf
│  │  │  ├─ backend.tf
│  │  │  └─ terraform.tfvars
│  │  │
│  │  └─ 30-apps/                         # Application deployments
│  │     └─ n8n/
│  │        ├─ main.tf
│  │        ├─ variables.tf
│  │        ├─ outputs.tf
│  │        ├─ backend.tf
│  │        └─ terraform.tfvars
│  │
│  └─ kubernetes/                         # Kubernetes configs (Phase 2+)
│     ├─ local/                           # kind/k3d for free practice
│     │  ├─ kind-config.yaml
│     │  └─ setup.sh
│     │
│     └─ aws-kops/                        # kOps for AWS burst
│        ├─ cluster.yaml
│        ├─ spin-up.sh
│        └─ tear-down.sh
│
├─ apps/                                  # Application configurations
│  │
│  ├─ n8n/
│  │  ├─ ecs/                             # ECS task definition
│  │  │  ├─ taskdef.json
│  │  │  └─ env.template
│  │  │
│  │  └─ k8s/                             # K8s manifests (Phase 2+)
│  │     ├─ deployment.yaml
│  │     ├─ service.yaml
│  │     └─ ingress.yaml
│  │
│  ├─ tax-api/                            # Future app
│  │  ├─ ecs/
│  │  └─ k8s/
│  │
│  └─ finance-api/                        # Future app
│     ├─ ecs/
│     └─ k8s/
│
├─ cicd/                                  # CI/CD configurations
│  │
│  ├─ github-actions/                     # GitHub Actions workflows
│  │  └─ workflows/
│  │     ├─ deploy-infra.yml
│  │     └─ deploy-app.yml
│  │
│  ├─ jenkins/                            # Jenkins pipelines
│  │  ├─ Jenkinsfile
│  │  └─ shared-library/
│  │
│  └─ argocd/                             # GitOps for K8s (Phase 2+)
│     ├─ apps/
│     └─ projects/
│
├─ helm/                                  # Helm charts (Phase 2+)
│  │
│  ├─ charts/
│  │  └─ nameless-app/                    # Generic app chart
│  │     ├─ Chart.yaml
│  │     ├─ values.yaml
│  │     └─ templates/
│  │
│  └─ values/                             # Per-app values
│     ├─ n8n/
│     ├─ tax-api/
│     └─ finance-api/
│
├─ observability/                         # Monitoring configs
│  │
│  ├─ dashboards/                         # Grafana dashboards (JSON)
│  ├─ alerts/                             # Alert rules
│  └─ collectors/                         # Fluent Bit, Telegraf configs
│
├─ scripts/                               # Utility scripts
│  ├─ deploy-all.sh                       # Deploy entire stack
│  ├─ destroy-all.sh                      # Tear down entire stack
│  ├─ rotate-nat.sh                       # Replace NAT instance
│  └─ backup-state.sh                     # Backup Terraform state
│
└─ _archive/                              # Old kOps setup (preserved)
   ├─ kops/
   ├─ modules-kops-cluster/
   ├─ envs-dev/
   └─ n8n-k8s/
```

### 3.2 Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| **Terraform files** | lowercase, hyphens | `main.tf`, `variables.tf` |
| **Modules** | lowercase, hyphens | `ecs-cluster`, `nat-instance` |
| **Variables** | snake_case | `vpc_cidr`, `cluster_name` |
| **Resources** | project-env-resource | `nameless-prod-vpc` |
| **Stacks** | numbered prefix | `00-state`, `10-network` |

### 3.3 Why Numbered Stack Prefixes?

The `00-`, `10-`, `20-` prefixes indicate **deployment order**:

```
00-state    → Must be deployed first (state backend)
10-network  → Depends on 00-state
20-ecs      → Depends on 10-network
30-apps/*   → Depends on 20-ecs
```

This makes it clear which stacks depend on which, and allows for inserting new stacks later (e.g., `15-security`, `25-databases`).

---

## 4. Terraform Modules

### 4.1 Module: networking

**Purpose**: Creates VPC with public and private subnets across 2 AZs.

**Location**: `infra/modules/networking/`

**Inputs**:
```hcl
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
```

**Outputs**:
```hcl
output "vpc_id" {}
output "vpc_cidr" {}
output "public_subnet_ids" {}
output "private_subnet_ids" {}
output "internet_gateway_id" {}
```

**Creates**:
- VPC
- Internet Gateway
- 2 Public Subnets (with public IP auto-assign)
- 2 Private Subnets
- Route Tables (public routes to IGW)

### 4.2 Module: nat-instance

**Purpose**: Creates a cost-effective NAT instance instead of NAT Gateway.

**Location**: `infra/modules/nat-instance/`

**Inputs**:
```hcl
variable "project_name" {}
variable "vpc_id" {}
variable "public_subnet_id" {}
variable "private_route_table_ids" {}
variable "instance_type" {
  default = "t3.micro"
}
```

**Outputs**:
```hcl
output "nat_instance_id" {}
output "nat_public_ip" {}
output "nat_security_group_id" {}
```

**Creates**:
- EC2 instance with NAT AMI
- Security Group (allow all outbound, allow inbound from VPC)
- Route table entries (private subnets → NAT instance)

### 4.3 Module: alb

**Purpose**: Creates Application Load Balancer with HTTP listener.

**Location**: `infra/modules/alb/`

**Inputs**:
```hcl
variable "project_name" {}
variable "vpc_id" {}
variable "public_subnet_ids" {}
variable "certificate_arn" {
  default = null  # For HTTPS (optional, we use Cloudflare)
}
```

**Outputs**:
```hcl
output "alb_arn" {}
output "alb_dns_name" {}
output "alb_zone_id" {}
output "alb_security_group_id" {}
output "http_listener_arn" {}
```

**Creates**:
- Application Load Balancer (internet-facing)
- Security Group (allow 80, 443 from anywhere)
- HTTP Listener (port 80)
- Default action (fixed 404 response)

### 4.4 Module: ecs-cluster

**Purpose**: Creates ECS cluster with Fargate Spot capacity provider.

**Location**: `infra/modules/ecs-cluster/`

**Inputs**:
```hcl
variable "project_name" {}
variable "enable_container_insights" {
  default = false  # Enable for ~$3/month extra
}
```

**Outputs**:
```hcl
output "cluster_arn" {}
output "cluster_name" {}
```

**Creates**:
- ECS Cluster
- Capacity Provider (FARGATE_SPOT as default, FARGATE as fallback)

### 4.5 Module: ecs-service

**Purpose**: Generic ECS service module for deploying any containerized app.

**Location**: `infra/modules/ecs-service/`

**Inputs**:
```hcl
variable "project_name" {}
variable "service_name" {}
variable "cluster_arn" {}
variable "vpc_id" {}
variable "private_subnet_ids" {}
variable "alb_listener_arn" {}
variable "alb_security_group_id" {}

# Container settings
variable "container_image" {}
variable "container_port" {}
variable "cpu" { default = 256 }      # 0.25 vCPU
variable "memory" { default = 512 }   # 512 MB
variable "desired_count" { default = 1 }

# Health check
variable "health_check_path" { default = "/" }

# Environment variables
variable "environment_variables" {
  type    = map(string)
  default = {}
}

# ALB routing
variable "host_header" {
  default = null  # For host-based routing
}
variable "path_pattern" {
  default = "/*"
}
```

**Outputs**:
```hcl
output "service_arn" {}
output "task_definition_arn" {}
output "target_group_arn" {}
output "log_group_name" {}
```

**Creates**:
- ECS Service
- Task Definition
- Target Group
- ALB Listener Rule
- CloudWatch Log Group
- Security Group (allow from ALB only)

### 4.6 Module: ecr

**Purpose**: Creates ECR repository for Docker images.

**Location**: `infra/modules/ecr/`

**Inputs**:
```hcl
variable "repository_name" {}
variable "image_tag_mutability" {
  default = "MUTABLE"
}
variable "lifecycle_policy" {
  description = "Keep only last N images"
  default     = 10
}
```

**Outputs**:
```hcl
output "repository_url" {}
output "repository_arn" {}
```

**Creates**:
- ECR Repository
- Lifecycle Policy (cleanup old images)

### 4.7 Module: iam

**Purpose**: Creates IAM roles for ECS tasks.

**Location**: `infra/modules/iam/`

**Submodules**:

#### ecs-task-execution/
```hcl
# Role that ECS uses to pull images and write logs
output "role_arn" {}
```

#### ecs-task-role/
```hcl
# Role that your application assumes (for AWS SDK calls)
variable "policy_arns" {
  description = "Additional policies to attach"
  type        = list(string)
  default     = []
}
output "role_arn" {}
```

---

## 5. Live Stacks

### 5.1 Stack: 00-state

**Purpose**: Bootstrap Terraform state backend.

**Location**: `infra/live/00-state/`

**Deploys**:
- S3 bucket for state files
- DynamoDB table for state locking

**Special**: This stack uses local state initially, then migrates.

**Deploy Command**:
```bash
cd infra/live/00-state
terraform init
terraform apply
```

### 5.2 Stack: 10-network

**Purpose**: Network infrastructure.

**Location**: `infra/live/10-network/`

**Uses Modules**:
- `networking`
- `nat-instance`

**Outputs**:
- `vpc_id`
- `public_subnet_ids`
- `private_subnet_ids`
- `nat_instance_id`

**Deploy Command**:
```bash
cd infra/live/10-network
terraform init
terraform apply
```

### 5.3 Stack: 20-ecs

**Purpose**: ECS platform infrastructure.

**Location**: `infra/live/20-ecs/`

**Uses Modules**:
- `alb`
- `ecs-cluster`
- `ecr` (for n8n repo)
- `iam/ecs-task-execution`

**Reads From**: `10-network` (via remote state)

**Outputs**:
- `alb_dns_name` ← **This is what you add to Cloudflare!**
- `cluster_arn`
- `ecr_repository_url`

**Deploy Command**:
```bash
cd infra/live/20-ecs
terraform init
terraform apply
```

### 5.4 Stack: 30-apps/n8n

**Purpose**: Deploy n8n application.

**Location**: `infra/live/30-apps/n8n/`

**Uses Modules**:
- `ecs-service`

**Reads From**: `10-network`, `20-ecs` (via remote state)

**Configuration**:
```hcl
container_image = "n8nio/n8n:latest"  # Or ECR image
container_port  = 5678
cpu             = 512   # 0.5 vCPU
memory          = 1024  # 1 GB
```

**Deploy Command**:
```bash
cd infra/live/30-apps/n8n
terraform init
terraform apply
```

---

## 6. Current Implementation (Phase 1)

### 6.1 What's Being Built Now

| Component | Status | Notes |
|-----------|--------|-------|
| VPC | To Build | 10.0.0.0/16, 2 AZs |
| NAT Instance | To Build | t3.micro, ~$5/month |
| ALB | To Build | HTTP only (HTTPS via Cloudflare) |
| ECS Cluster | To Build | Fargate Spot |
| ECR | To Build | n8n repository |
| n8n Service | To Build | 0.5 vCPU, 1GB RAM |

### 6.2 n8n Configuration

**Container Settings**:
```
Image: n8nio/n8n:latest
Port: 5678
CPU: 512 (0.5 vCPU)
Memory: 1024 MB
```

**Environment Variables**:
```
N8N_PORT=5678
N8N_PROTOCOL=http
GENERIC_TIMEZONE=Europe/Berlin
N8N_HOST=n8n.yourdomain.com
WEBHOOK_URL=https://n8n.yourdomain.com/
```

**Health Check**:
```
Path: /healthz
Interval: 30s
Timeout: 5s
```

### 6.3 Expected Outputs

After Phase 1 deployment:

```bash
$ terraform output -raw alb_dns_name
nameless-alb-123456789.eu-central-1.elb.amazonaws.com
```

**Cloudflare Setup**:
1. Add CNAME: `n8n.yourdomain.com` → `alb_dns_name`
2. Enable Cloudflare Proxy (orange cloud)
3. SSL Mode: Full

---

## 7. Future Expansions

### 7.1 Phase 2: More Applications

**When**: After n8n is stable

**Add**:
```
infra/live/30-apps/
├─ n8n/           # ✓ Done
├─ tax-api/       # Phase 2
├─ finance-api/   # Phase 2
└─ rag-api/       # Phase 2
```

**Each app needs**:
1. ECR repository (add to `20-ecs`)
2. ECS service stack (new `30-apps/<app>/`)
3. ALB listener rule (host-based routing)

**ALB Routing Example**:
```
n8n.yourdomain.com     → n8n service
tax.yourdomain.com     → tax-api service
finance.yourdomain.com → finance-api service
```

### 7.2 Phase 3: Local Kubernetes

**When**: Ready for CKA/CKAD daily practice

**Add**:
```
infra/kubernetes/local/
├─ kind-config.yaml
├─ setup.sh
└─ teardown.sh
```

**kind Configuration**:
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
```

**Cost**: $0 (runs on your laptop)

### 7.3 Phase 4: AWS Kubernetes (Burst)

**When**: Need AWS-specific practice (kOps, EKS)

**Add**:
```
infra/kubernetes/aws-kops/
├─ cluster.yaml
├─ spin-up.sh
└─ tear-down.sh
```

**Minimal kOps Config**:
- 1 master (t3.small spot)
- 1-2 workers (t3.small spot)
- Same VPC as ECS (reuse networking)

**Cost**: ~$20-30/month if running 24/7 (but don't!)

**Strategy**: Spin up Friday night → Practice weekend → Tear down Sunday

### 7.4 Phase 5: CI/CD

**When**: Tired of manual deployments

**Options**:

| Tool | Use Case | Where |
|------|----------|-------|
| GitHub Actions | Simple, free for public repos | `cicd/github-actions/` |
| Jenkins | Company-relevant, more control | `cicd/jenkins/` |
| ArgoCD | GitOps for K8s | `cicd/argocd/` |

**ECS Deployment Pipeline**:
```
Push to main → Build Docker image → Push to ECR → Update ECS service
```

**K8s Deployment Pipeline** (GitOps):
```
Push to main → ArgoCD detects → Syncs to cluster
```

### 7.5 Phase 6: Observability

**When**: Need better visibility

**Progression**:
1. **Now**: CloudWatch Logs (automatic with ECS)
2. **Phase 6a**: CloudWatch Dashboards + Alarms
3. **Phase 6b**: Grafana Cloud (free tier)
4. **Phase 6c**: Self-hosted Prometheus + Grafana (on K8s)

**Add**:
```
observability/
├─ dashboards/
│  ├─ ecs-overview.json
│  └─ n8n-metrics.json
├─ alerts/
│  ├─ cloudwatch-alarms.tf
│  └─ prometheus-rules.yaml
└─ collectors/
   └─ fluent-bit.conf
```

### 7.6 Phase 7: Databases

**When**: Apps need persistent data

**Options**:

| Option | Cost | Use Case |
|--------|------|----------|
| **RDS (t3.micro)** | ~$15/month | Production-ready, managed |
| **RDS Serverless v2** | Pay per use | Variable load |
| **EFS** | ~$0.30/GB | Shared file storage |
| **S3** | ~$0.023/GB | Object storage |

**For n8n**: Start with SQLite (local storage), migrate to RDS when needed.

### 7.7 Phase 8: Secrets Management

**When**: Need secure secret storage

**Options**:

| Option | Cost | Integration |
|--------|------|-------------|
| **AWS Secrets Manager** | $0.40/secret/month | Native ECS integration |
| **AWS SSM Parameter Store** | Free (standard) | Good for configs |
| **HashiCorp Vault** | Free (self-hosted) | Advanced, K8s-friendly |

**Recommendation**: Start with SSM Parameter Store (free), move to Secrets Manager for rotation.

---

## 8. Cost Analysis

### 8.1 Phase 1 Detailed Breakdown

| Resource | Type | Monthly Cost |
|----------|------|-------------|
| **VPC** | - | $0 |
| **Internet Gateway** | - | $0 |
| **NAT Instance** | t3.micro | ~$3-5 |
| **ALB** | Per hour + LCU | ~$16-22 |
| **ECS Cluster** | Control plane | $0 |
| **Fargate Spot (n8n)** | 0.5 vCPU, 1GB | ~$5-8 |
| **ECR** | Storage | ~$1 |
| **CloudWatch Logs** | ~5GB | ~$2.50 |
| **S3 (state)** | < 1GB | ~$0.10 |
| **DynamoDB (lock)** | Minimal | ~$0.25 |
| **Data Transfer** | Out to internet | ~$1-2 |
| **TOTAL** | | **~$30-40/month** |

### 8.2 Cost Optimization Tips

1. **Use Fargate Spot** - 70% savings over on-demand
2. **NAT Instance over NAT Gateway** - $27/month savings
3. **Single AZ for NAT** - Acceptable for personal project
4. **CloudWatch Logs retention** - Set to 7 days (reduce storage)
5. **ECR lifecycle policy** - Keep only last 10 images
6. **Scheduled scaling** - Scale to 0 at night (if not needed)

### 8.3 Cost Alerts

Set up AWS Budgets:
```
Budget: $50/month
Alert at: 50%, 80%, 100%
Action: Email notification
```

### 8.4 Future Cost Projections

| Phase | Components | Monthly Estimate |
|-------|------------|-----------------|
| Phase 1 | n8n only | $30-40 |
| Phase 2 | + 2 more apps | $45-60 |
| Phase 3 | + local K8s | $45-60 (no change) |
| Phase 4 | + AWS K8s (burst) | $60-80 |
| Phase 5 | + CI/CD | $60-80 (no change) |
| Phase 6 | + Observability | $65-85 |
| Phase 7 | + RDS | $80-100 |

---

## 9. Security Considerations

### 9.1 Network Security

**VPC Design**:
- ✅ Private subnets for workloads (no public IPs)
- ✅ ALB in public subnet (only entry point)
- ✅ NAT instance for outbound (controlled egress)

**Security Groups**:
```
ALB SG:
  Inbound: 80, 443 from 0.0.0.0/0
  Outbound: All to VPC

ECS Tasks SG:
  Inbound: Container port from ALB SG only
  Outbound: All (for NAT)

NAT Instance SG:
  Inbound: All from VPC CIDR
  Outbound: All to 0.0.0.0/0
```

### 9.2 IAM Security

**Principle of Least Privilege**:
- Task Execution Role: Only ECR pull + CloudWatch logs
- Task Role: Only what the app needs (e.g., S3 read for specific bucket)

**Example Task Role Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::my-bucket/*"
    }
  ]
}
```

### 9.3 Secrets Management

**DO**:
- ✅ Store secrets in SSM Parameter Store or Secrets Manager
- ✅ Reference secrets in task definition (not hardcode)
- ✅ Use IAM roles (not access keys)

**DON'T**:
- ❌ Hardcode secrets in code
- ❌ Store secrets in environment variables (visible in console)
- ❌ Commit secrets to git

**ECS Secret Reference**:
```json
{
  "secrets": [
    {
      "name": "DATABASE_PASSWORD",
      "valueFrom": "arn:aws:ssm:eu-central-1:123456789:parameter/n8n/db-password"
    }
  ]
}
```

### 9.4 SSL/TLS Strategy

**Current Strategy** (Cloudflare):
```
User → HTTPS → Cloudflare → HTTP → ALB → ECS
```

**Pros**:
- Free SSL certificate
- DDoS protection
- Easy setup

**Cons**:
- Traffic between Cloudflare and ALB is HTTP (but within AWS)

**Future Enhancement** (Full HTTPS):
```
User → HTTPS → Cloudflare → HTTPS → ALB → ECS
```
- Requires ACM certificate
- Set Cloudflare SSL mode to "Full (strict)"

### 9.5 Security Checklist

- [ ] No public IPs on ECS tasks
- [ ] Security groups restrict traffic appropriately
- [ ] IAM roles follow least privilege
- [ ] Secrets stored in SSM/Secrets Manager
- [ ] CloudTrail enabled for audit logs
- [ ] VPC Flow Logs enabled (optional, adds cost)
- [ ] AWS Config rules for compliance (optional)

---

## 10. Operational Runbooks

### 10.1 Deploy Entire Stack

```bash
#!/bin/bash
# scripts/deploy-all.sh

set -e

echo "🚀 Deploying Nameless Company Infrastructure"

# 1. State backend (only first time)
echo "📦 Setting up state backend..."
cd infra/live/00-state
terraform init
terraform apply -auto-approve

# 2. Network
echo "🌐 Deploying network..."
cd ../10-network
terraform init
terraform apply -auto-approve

# 3. ECS Platform
echo "🐳 Deploying ECS platform..."
cd ../20-ecs
terraform init
terraform apply -auto-approve

# 4. Applications
echo "📱 Deploying n8n..."
cd ../30-apps/n8n
terraform init
terraform apply -auto-approve

echo "✅ Deployment complete!"
echo "ALB DNS: $(terraform output -raw alb_dns_name)"
```

### 10.2 Destroy Entire Stack

```bash
#!/bin/bash
# scripts/destroy-all.sh

set -e

echo "🗑️ Destroying Nameless Company Infrastructure"
echo "⚠️ This will delete ALL resources!"
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Aborted."
  exit 1
fi

# Destroy in reverse order
cd infra/live/30-apps/n8n
terraform destroy -auto-approve

cd ../../20-ecs
terraform destroy -auto-approve

cd ../10-network
terraform destroy -auto-approve

# Keep state backend (or destroy manually if needed)
echo "⚠️ State backend NOT destroyed. Delete manually if needed."

echo "✅ Infrastructure destroyed!"
```

### 10.3 Add a New Application

**Steps**:

1. **Create ECR repository** (in `20-ecs`):
```hcl
module "tax_api_ecr" {
  source          = "../../modules/ecr"
  repository_name = "tax-api"
}
```

2. **Create app stack**:
```bash
mkdir -p infra/live/30-apps/tax-api
```

3. **Create main.tf**:
```hcl
module "tax_api" {
  source = "../../../modules/ecs-service"
  
  project_name       = "nameless"
  service_name       = "tax-api"
  cluster_arn        = data.terraform_remote_state.ecs.outputs.cluster_arn
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  alb_listener_arn   = data.terraform_remote_state.ecs.outputs.http_listener_arn
  alb_security_group_id = data.terraform_remote_state.ecs.outputs.alb_security_group_id
  
  container_image = "your-account.dkr.ecr.eu-central-1.amazonaws.com/tax-api:latest"
  container_port  = 8080
  cpu             = 256
  memory          = 512
  
  host_header = "tax.yourdomain.com"
}
```

4. **Deploy**:
```bash
cd infra/live/30-apps/tax-api
terraform init
terraform apply
```

5. **Add Cloudflare DNS**:
```
CNAME: tax.yourdomain.com → alb_dns_name
```

### 10.4 Update an Application

**Option 1: New Docker Image**
```bash
# Build and push new image
docker build -t your-account.dkr.ecr.eu-central-1.amazonaws.com/n8n:v2 .
docker push your-account.dkr.ecr.eu-central-1.amazonaws.com/n8n:v2

# Update Terraform and apply
cd infra/live/30-apps/n8n
# Update container_image in main.tf
terraform apply
```

**Option 2: Force New Deployment (same image tag)**
```bash
aws ecs update-service \
  --cluster nameless-cluster \
  --service n8n \
  --force-new-deployment
```

### 10.5 View Logs

**CloudWatch Logs**:
```bash
# Stream logs
aws logs tail /ecs/nameless-n8n --follow

# Get recent logs
aws logs get-log-events \
  --log-group-name /ecs/nameless-n8n \
  --log-stream-name $(aws logs describe-log-streams \
    --log-group-name /ecs/nameless-n8n \
    --order-by LastEventTime \
    --descending \
    --limit 1 \
    --query 'logStreams[0].logStreamName' \
    --output text)
```

### 10.6 Troubleshooting

**Service not starting?**
```bash
# Check service events
aws ecs describe-services \
  --cluster nameless-cluster \
  --services n8n \
  --query 'services[0].events[:5]'

# Check task failures
aws ecs describe-tasks \
  --cluster nameless-cluster \
  --tasks $(aws ecs list-tasks --cluster nameless-cluster --service-name n8n --query 'taskArns[0]' --output text)
```

**Can't reach service?**
1. Check ALB target group health
2. Check security group rules
3. Check CloudWatch Logs for app errors
4. Check task is running in correct subnet

**NAT Instance issues?**
```bash
# Check NAT instance status
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*nat*" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]'

# Reboot if needed
aws ec2 reboot-instances --instance-ids i-xxxxx
```

---

## 11. Content Creation Notes

### 11.1 YouTube Video Ideas

| Video | Topic | Key Points |
|-------|-------|------------|
| 1 | "Building a Personal Cloud Platform on AWS" | Overview, goals, cost targets |
| 2 | "ECS vs Kubernetes: When to Use Each" | Cost comparison, use cases |
| 3 | "NAT Instance vs NAT Gateway: $27/month Savings" | Setup, trade-offs |
| 4 | "Deploying n8n on AWS ECS" | Step-by-step tutorial |
| 5 | "Terraform Modules: Best Practices" | Module design, reusability |
| 6 | "AWS Cost Optimization for Personal Projects" | Tips and tricks |
| 7 | "Local Kubernetes with kind for CKA Prep" | Free practice setup |
| 8 | "GitOps with ArgoCD" | When you add K8s |

### 11.2 Blog Post Topics

1. "How I Reduced My AWS Bill from $80 to $30"
2. "ECS Fargate Spot: The Hidden Cost Saver"
3. "Terraform Project Structure: Modules vs Live Stacks"
4. "CloudWatch vs Prometheus: When to Use Each"
5. "Preparing for CKA Without Breaking the Bank"

### 11.3 What Makes This Setup Interesting

1. **Hybrid Approach**: ECS for production, K8s for learning
2. **Cost Optimization**: NAT Instance, Fargate Spot
3. **Real Infrastructure**: Not just tutorials, actual working apps
4. **Modular Design**: Professional Terraform patterns
5. **Growth Path**: Clear phases for expansion

### 11.4 Content Schedule Suggestion

| Week | Focus | Content |
|------|-------|---------|
| 1 | Build | Deploy infrastructure, document process |
| 2 | Polish | Fix issues, optimize, write blog post |
| 3 | Record | Create YouTube video |
| 4 | Expand | Add new feature, repeat cycle |

---

## Appendix A: Quick Reference Commands

### Terraform
```bash
# Init with backend
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply

# Apply without prompt
terraform apply -auto-approve

# Destroy
terraform destroy

# Show outputs
terraform output

# Import existing resource
terraform import aws_instance.example i-xxxxx
```

### AWS CLI
```bash
# Configure SSO
aws configure sso

# Login
aws sso login --profile your-profile

# ECS commands
aws ecs list-clusters
aws ecs list-services --cluster nameless-cluster
aws ecs describe-services --cluster nameless-cluster --services n8n

# ECR commands
aws ecr get-login-password | docker login --username AWS --password-stdin your-account.dkr.ecr.eu-central-1.amazonaws.com
aws ecr describe-repositories

# Logs
aws logs tail /ecs/nameless-n8n --follow
```

### Docker
```bash
# Build image
docker build -t n8n:local .

# Tag for ECR
docker tag n8n:local your-account.dkr.ecr.eu-central-1.amazonaws.com/n8n:latest

# Push to ECR
docker push your-account.dkr.ecr.eu-central-1.amazonaws.com/n8n:latest
```

---

## Appendix B: Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Dec 2024 | Initial plan - ECS foundation |
| | | |

---

## Appendix C: Contacts & Resources

### AWS Resources
- [ECS Developer Guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Pricing Calculator](https://calculator.aws/)

### Learning Resources
- [CKA Curriculum](https://github.com/cncf/curriculum)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [n8n Documentation](https://docs.n8n.io/)

---

*This document is a living reference. Update as the infrastructure evolves.*
