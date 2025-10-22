# Nameless Company Infrastructure

> Cost-optimized AWS infrastructure automation using Terraform

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Terraform](https://img.shields.io/badge/Terraform-1.5+-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Cloud-FF9900?logo=amazon-aws)](https://aws.amazon.com/)

## Overview

This repository contains Terraform infrastructure-as-code for provisioning cost-optimized AWS resources. The current implementation focuses on establishing a secure, production-ready backend for Terraform state management.

## What's Included

### Terraform Backend Infrastructure

**Location**: `terraform/backend/`

Automated setup for:
- **S3 Bucket** - Encrypted, versioned storage for Terraform state
- **DynamoDB Table** - State locking to prevent concurrent modifications
- **Security Policies** - Enforce HTTPS, encryption, and access controls

### Features

✅ **Versioned State** - Full history of infrastructure changes  
✅ **State Locking** - Prevents concurrent modifications  
✅ **Encryption** - AES-256 encryption at rest  
✅ **Cost Optimized** - Lifecycle policies reduce storage costs  
✅ **AWS SSO Support** - Seamless authentication workflow  

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2
- AWS account with appropriate permissions
- [aws2-wrap](https://github.com/linaro-its/aws2-wrap) (for AWS SSO)

```bash
# Install aws2-wrap
pip install aws2-wrap
```

## Quick Start

### 1. Configure AWS SSO

```bash
# Login to AWS SSO
aws sso login --profile=default

# Verify access
aws sts get-caller-identity --profile default
```

See [docs/aws-sso-setup.md](docs/aws-sso-setup.md) for detailed setup instructions.

### 2. Deploy Backend Infrastructure

```bash
cd terraform/backend

# Initialize Terraform
aws2-wrap --profile default terraform init

# Review planned changes
aws2-wrap --profile default terraform plan

# Deploy infrastructure
aws2-wrap --profile default terraform apply
```

### 3. Configure Remote State (Future Projects)

After deployment, use these outputs in other Terraform projects:

```hcl
terraform {
  backend "s3" {
    bucket         = "<output: terraform_state_bucket>"
    key            = "path/to/my/state.tfstate"
    region         = "us-east-1"
    dynamodb_table = "<output: dynamodb_table_name>"
    encrypt        = true
  }
}
```

## Repository Structure

```
.
├── docs/
│   └── aws-sso-setup.md          # AWS SSO configuration guide
├── scripts/
│   └── terraform-with-sso.sh     # Helper script for Terraform with SSO
└── terraform/
    └── backend/
        ├── main.tf               # Backend infrastructure resources
        ├── variables.tf          # Input variables
        ├── outputs.tf            # Output values
        └── backend.tf            # Backend configuration
```

## Cost Optimization

This setup is designed for minimal cost:

| Resource | Monthly Cost |
|----------|--------------|
| S3 Storage (< 1GB) | ~$0.02 |
| DynamoDB (on-demand) | ~$0.01 |
| **Total** | **~$0.05/month** |

Lifecycle policies automatically:
- Transition old versions to IA storage after 30 days
- Delete old versions after 90 days

## Security Features

- 🔒 **Encryption at rest** - AES-256 for S3 and DynamoDB
- 🔐 **HTTPS enforcement** - Deny all non-HTTPS requests
- 🔑 **Bucket versioning** - Protect against accidental deletion
- 🚫 **Public access blocked** - All S3 buckets are private
- 📊 **Point-in-time recovery** - DynamoDB backup enabled

## Usage Examples

### Deploy with Different AWS Profiles

```bash
# Use specific AWS SSO profile
aws2-wrap --profile my-profile terraform apply
```

### Destroy Infrastructure

```bash
cd terraform/backend
aws2-wrap --profile default terraform destroy
```

⚠️ **Warning**: This will delete all Terraform state. Ensure you have backups!

## Troubleshooting

### Issue: "Error acquiring the state lock"

**Cause**: Another Terraform process is running or crashed without releasing the lock.

**Solution**:
```bash
# Force unlock (use with caution!)
terraform force-unlock <LOCK_ID>
```

### Issue: "Failed to retrieve credentials"

**Cause**: AWS SSO session expired.

**Solution**:
```bash
# Re-authenticate
aws sso login --profile=default
```

## Contributing

This is a personal infrastructure repository, but suggestions and improvements are welcome!

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit your changes (`git commit -am 'Add improvement'`)
4. Push to the branch (`git push origin feature/improvement`)
5. Create a Pull Request

## License

MIT License - See [LICENSE](LICENSE) for details

## Author

Infrastructure automation for cost-optimized cloud deployments.

---

**Status**: ✅ Phase 1 Complete - Backend Infrastructure  
**Next Phase**: VPC and networking infrastructure
