# =============================================================================
# 30-apps/hello-django - Demo Django Application for CI/CD Testing
# Tests the auto-create service discovery feature
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
    key            = "live/30-apps/hello-django/terraform.tfstate"
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
      Application = "hello-django"
    }
  }
}

# -----------------------------------------------------------------------------
# Remote State Data Sources
# -----------------------------------------------------------------------------
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "nameless-terraform-state"
    key    = "live/10-network/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "ecs" {
  backend = "s3"

  config = {
    bucket = "nameless-terraform-state"
    key    = "live/20-ecs/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "cloudflare" {
  backend = "s3"

  config = {
    bucket = "nameless-terraform-state"
    key    = "live/05-cloudflare/terraform.tfstate"
    region = "us-east-1"
  }
}

# -----------------------------------------------------------------------------
# hello-django ECS Service using the ecs-service module
# Uses Service Discovery for Cloudflare Tunnel routing - NO ALB
# -----------------------------------------------------------------------------
module "hello_django_service" {
  source = "../../../modules/ecs-service"

  project_name = var.project_name
  service_name = "hello-django"
  aws_region   = var.aws_region

  # ECS Configuration
  cluster_arn             = data.terraform_remote_state.ecs.outputs.cluster_arn
  task_execution_role_arn = data.terraform_remote_state.ecs.outputs.task_execution_role_arn

  # EC2 Capacity Provider
  capacity_provider_name = data.terraform_remote_state.ecs.outputs.capacity_provider_name
  launch_type            = "EC2"

  # Network Configuration
  vpc_id                = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids    = data.terraform_remote_state.network.outputs.private_subnet_ids
  alb_security_group_id = data.terraform_remote_state.cloudflare.outputs.cloudflared_security_group_id  # Allow from cloudflared

  # NO ALB - Use Cloudflare Tunnel via Service Discovery
  enable_alb             = false
  alb_listener_arn       = ""  # Not used
  path_pattern           = ""  # Not used
  listener_rule_priority = 0   # Not used
  health_check_path      = "/"

  # Container Configuration
  container_image = var.container_image
  container_port  = 8000
  cpu             = 256
  memory          = 512

  # Environment Variables
  environment_variables = {
    DJANGO_SETTINGS_MODULE = "hello_django.settings"
    DEBUG                  = "False"
    ALLOWED_HOSTS          = "*"
  }

  # Cloudflare Tunnel Integration - allow cloudflared to access this service
  cloudflared_security_group_id = data.terraform_remote_state.cloudflare.outputs.cloudflared_security_group_id

  # Service Discovery - AUTO-CREATE hello-django.nameless.local for cloudflared routing
  enable_service_discovery = true
  cloudmap_namespace_id    = data.terraform_remote_state.network.outputs.service_discovery_namespace_id
  service_discovery_name   = "hello-django"  # Results in: hello-django.nameless.local

  tags = var.tags
}
