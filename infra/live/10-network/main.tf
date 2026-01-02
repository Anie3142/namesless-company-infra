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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
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
# NAT Instance Module (also acts as bastion host for DB access)
# -----------------------------------------------------------------------------
module "nat_instance" {
  source = "../../modules/nat-instance"

  project_name            = var.project_name
  vpc_id                  = module.networking.vpc_id
  vpc_cidr                = module.networking.vpc_cidr
  public_subnet_id        = module.networking.public_subnet_ids[0]
  private_route_table_ids = module.networking.private_route_table_ids
  instance_type           = var.nat_instance_type
  admin_ip_addresses      = var.admin_ip_addresses

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Cloud Map Service Discovery Namespace
# Used for internal VPC DNS resolution (e.g., jenkins.nameless.local)
# Services register here and cloudflared uses this to route traffic
# -----------------------------------------------------------------------------
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${var.project_name}.local"
  description = "Private DNS namespace for service discovery"
  vpc         = module.networking.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project_name}-service-discovery-namespace"
  })
}

# Jenkins Service Discovery
resource "aws_service_discovery_service" "jenkins" {
  name = "jenkins"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-jenkins-service-discovery"
  })
}

# n8n Service Discovery
resource "aws_service_discovery_service" "n8n" {
  name = "n8n"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 60
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-n8n-service-discovery"
  })
}
