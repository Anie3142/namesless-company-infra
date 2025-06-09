# Terraform Backend Bootstrap
# This creates the S3 bucket and DynamoDB table for remote state management
# Run this first, then migrate to remote backend

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "kops-infra"
      Environment = "bootstrap"
      ManagedBy   = "terraform"
      CostCenter  = "infrastructure"
    }
  }
}

# Random suffix for globally unique bucket names
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 buckets configuration
locals {
  buckets = {
    terraform-state = {
      name_prefix = "terraform-state-kops"
      purpose     = "Terraform remote state storage"
    }
    kops-state = {
      name_prefix = "kops-state"
      purpose     = "kOps cluster state storage"
    }
  }
}

# S3 buckets with cost optimization
resource "aws_s3_bucket" "buckets" {
  for_each = local.buckets
  bucket   = "${each.value.name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Purpose = each.value.purpose
  }
}

# S3 bucket versioning (cost-optimized)
resource "aws_s3_bucket_versioning" "buckets" {
  for_each = aws_s3_bucket.buckets
  bucket   = each.value.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket lifecycle for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "buckets" {
  for_each = aws_s3_bucket.buckets
  bucket   = each.value.id

  rule {
    id     = "cost_optimization"
    status = "Enabled"

    # Apply to all objects
    filter {}

    # Delete old versions after 30 days to save costs
    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    # Move to IA after 30 days (minimal cost for state files)
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "buckets" {
  for_each = aws_s3_bucket.buckets
  bucket   = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # Free encryption vs KMS
    }
    bucket_key_enabled = true  # Reduces KMS costs if we switch later
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each = aws_s3_bucket.buckets
  bucket   = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy - enforce HTTPS only
resource "aws_s3_bucket_policy" "buckets" {
  for_each = aws_s3_bucket.buckets
  bucket   = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          each.value.arn,
          "${each.value.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name           = "terraform-state-locks"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "Terraform State Locks"
  }
}
