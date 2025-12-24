# =============================================================================
# 10-network - Network Infrastructure
# Creates VPC, subnets, and NAT instance
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "nameless-terraform-state"
    key            = "live/10-network/terraform.tfstate"
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
# Networking Module
# -----------------------------------------------------------------------------
module "networking" {
  source = "../../modules/networking"

  project_name    = var.project_name
  vpc_cidr        = var.vpc_cidr
  azs             = var.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  tags = var.tags
}

# -----------------------------------------------------------------------------
# NAT Instance Module
# -----------------------------------------------------------------------------
module "nat_instance" {
  source = "../../modules/nat-instance"

  project_name            = var.project_name
  vpc_id                  = module.networking.vpc_id
  vpc_cidr                = module.networking.vpc_cidr
  public_subnet_id        = module.networking.public_subnet_ids[0]
  private_route_table_ids = module.networking.private_route_table_ids
  instance_type           = var.nat_instance_type

  tags = var.tags
}
