# =============================================================================
# 15-database - Shared RDS PostgreSQL Database
# For n8n, pgvector, and future applications
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket         = "nameless-terraform-state"
    key            = "live/15-database/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "nameless-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Environment = "production"
    }
  }
}

# -----------------------------------------------------------------------------
# Remote State Data Source - Network
# -----------------------------------------------------------------------------
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "nameless-terraform-state"
    key    = "live/10-network/terraform.tfstate"
    region = "us-east-1"
  }
}

# -----------------------------------------------------------------------------
# Generate random password for database
# -----------------------------------------------------------------------------
resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# -----------------------------------------------------------------------------
# Store password in SSM Parameter Store (FREE)
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "db_password" {
  name        = "/${var.project_name}/database/master-password"
  description = "Master password for ${var.project_name} PostgreSQL database"
  type        = "SecureString"
  value       = random_password.db_password.result

  tags = {
    Name = "${var.project_name}-db-password"
  }
}

# Also store the n8n encryption key
resource "random_password" "n8n_encryption_key" {
  length  = 32
  special = false  # n8n prefers alphanumeric
}

resource "aws_ssm_parameter" "n8n_encryption_key" {
  name        = "/${var.project_name}/n8n/encryption-key"
  description = "Encryption key for n8n credentials"
  type        = "SecureString"
  value       = random_password.n8n_encryption_key.result

  tags = {
    Name = "${var.project_name}-n8n-encryption-key"
  }
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL Module
# -----------------------------------------------------------------------------
module "postgres" {
  source = "../../modules/rds-postgres"

  project_name = var.project_name
  name         = "main"

  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  # Allow connections from private subnets (where ECS tasks run)
  allowed_cidr_blocks = data.terraform_remote_state.network.outputs.private_subnet_cidrs

  # Instance configuration
  instance_class        = var.db_instance_class
  engine_version        = "15"
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage

  # Database configuration
  database_name   = "n8n"  # Initial database for n8n
  master_username = "postgres"
  master_password = random_password.db_password.result

  # Backup & HA
  backup_retention_days = 7
  multi_az              = false  # Set true in production

  # Deletion protection (disable for dev)
  deletion_protection = false
  skip_final_snapshot = true

  tags = var.tags
}
