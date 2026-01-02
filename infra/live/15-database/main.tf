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
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.21"
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

  # Allow connections from:
  # - Private subnets (where ECS tasks run)
  # - Public subnets (for bastion/SSH tunnel access)
  allowed_cidr_blocks = concat(
    data.terraform_remote_state.network.outputs.private_subnet_cidrs,
    data.terraform_remote_state.network.outputs.public_subnet_cidrs
  )

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

# =============================================================================
# App-Specific Database SSM Parameters
# =============================================================================
# These SSM parameters store DATABASE_URLs for each application
# The format uses postgresql:// (Django compatible) with URL-encoded password
# 
# NOTE: PostgreSQL provider requires network access to RDS. Since RDS is in 
# private subnets, you may need to create databases manually via:
#   - psql from a bastion host
#   - Running a one-time ECS task
#   - SSH tunnel through NAT instance
# =============================================================================

locals {
  # URL-encode the password for use in DATABASE_URL
  db_password_encoded = urlencode(random_password.db_password.result)
  db_host             = module.postgres.address
  db_port             = module.postgres.port
  db_username         = "postgres"
  
  # List of app databases to create SSM parameters for
  app_databases = var.app_databases
}

# Create SSM parameters for each app's DATABASE_URL
resource "aws_ssm_parameter" "app_database_urls" {
  for_each = local.app_databases

  name        = "/${var.project_name}/${each.key}/database-url"
  description = "DATABASE_URL for ${each.key} application"
  type        = "SecureString"
  value       = "postgresql://${local.db_username}:${local.db_password_encoded}@${local.db_host}:${local.db_port}/${each.value.database_name}"
  overwrite   = true  # Allow updating existing parameters

  tags = {
    Name        = "${var.project_name}-${each.key}-database-url"
    Application = each.key
  }
}

# =============================================================================
# N8N DATABASE_URL (for n8n app compatibility)
# =============================================================================
resource "aws_ssm_parameter" "n8n_database_url" {
  name        = "/${var.project_name}/n8n/database-url"
  description = "DATABASE_URL for n8n"
  type        = "SecureString"
  value       = "postgresql://${local.db_username}:${local.db_password_encoded}@${local.db_host}:${local.db_port}/n8n"

  tags = {
    Name        = "${var.project_name}-n8n-database-url"
    Application = "n8n"
  }
}
