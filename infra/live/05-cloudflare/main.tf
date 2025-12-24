# =============================================================================
# 05-cloudflare - Cloudflare Infrastructure
# Manages DNS, Access, and Tunnel via Terraform
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
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
    key            = "live/05-cloudflare/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "nameless-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# Get Cloudflare credentials from SSM Parameter Store
data "aws_ssm_parameter" "cloudflare_api_token" {
  name            = "/nameless/cloudflare/api-token"
  with_decryption = true
}

data "aws_ssm_parameter" "cloudflare_zone_id" {
  name = "/nameless/cloudflare/zone-id"
}

data "aws_ssm_parameter" "cloudflare_account_id" {
  name = "/nameless/cloudflare/account-id"
}

provider "cloudflare" {
  api_token = data.aws_ssm_parameter.cloudflare_api_token.value
}

# Local variables
locals {
  zone_id    = data.aws_ssm_parameter.cloudflare_zone_id.value
  account_id = data.aws_ssm_parameter.cloudflare_account_id.value
  domain     = "namelesscompany.cc"
  
  # ALB DNS (current origin - will be replaced by tunnel later)
  alb_dns = var.alb_dns_name
}

# -----------------------------------------------------------------------------
# DNS Records
# -----------------------------------------------------------------------------

# Jenkins UI DNS
resource "cloudflare_record" "jenkins" {
  zone_id = local.zone_id
  name    = "jenkins"
  content = local.alb_dns
  type    = "CNAME"
  ttl     = 1  # Auto (proxied)
  proxied = true

  comment = "Jenkins CI/CD UI - managed by Terraform"
}

# Webhook DNS (separate hostname for GitHub webhooks)
resource "cloudflare_record" "webhook" {
  zone_id = local.zone_id
  name    = "webhook"
  content = local.alb_dns
  type    = "CNAME"
  ttl     = 1
  proxied = true

  comment = "GitHub webhook endpoint - managed by Terraform"
}

# -----------------------------------------------------------------------------
# Cloudflare Access Application (Jenkins UI only)
# NOTE: Access is managed manually in Cloudflare Dashboard for now
# The API token needs Account-level Access permissions to manage via Terraform
# -----------------------------------------------------------------------------

# resource "cloudflare_access_application" "jenkins" {
#   zone_id          = local.zone_id
#   name             = "Jenkins UI"
#   domain           = "jenkins.${local.domain}"
#   type             = "self_hosted"
#   session_duration = "24h"
#   auto_redirect_to_identity = false
# }

# resource "cloudflare_access_policy" "jenkins_allow" {
#   zone_id        = local.zone_id
#   application_id = cloudflare_access_application.jenkins.id
#   name           = "Allow Jenkins Admins"
#   precedence     = 1
#   decision       = "allow"
#   include {
#     email = var.allowed_emails
#   }
# }

# -----------------------------------------------------------------------------
# Cloudflare Tunnel (for ALB replacement)
# -----------------------------------------------------------------------------

resource "cloudflare_tunnel" "nameless" {
  account_id = local.account_id
  name       = "nameless-tunnel"
  secret     = random_id.tunnel_secret.b64_std
}

resource "random_id" "tunnel_secret" {
  byte_length = 32
}

# Store tunnel token in SSM for cloudflared ECS service
resource "aws_ssm_parameter" "tunnel_token" {
  name        = "/nameless/cloudflare/tunnel-token"
  description = "Cloudflare Tunnel token for cloudflared"
  type        = "SecureString"
  value       = cloudflare_tunnel.nameless.tunnel_token

  tags = {
    Name      = "nameless-cloudflare-tunnel-token"
    ManagedBy = "Terraform"
  }
}

# Tunnel configuration (ingress rules)
# Points to internal ALB - cloudflared runs as separate ECS service
resource "cloudflare_tunnel_config" "nameless" {
  account_id = local.account_id
  tunnel_id  = cloudflare_tunnel.nameless.id

  config {
    # Jenkins UI - routes to internal ALB
    ingress_rule {
      hostname = "jenkins.${local.domain}"
      service  = "http://${local.alb_dns}:80"
      origin_request {
        http_host_header = "jenkins.${local.domain}"
      }
    }

    # Jenkins TEST - same routing for testing
    ingress_rule {
      hostname = "jenkins-test.${local.domain}"
      service  = "http://${local.alb_dns}:80"
      origin_request {
        http_host_header = "jenkins.${local.domain}"
      }
    }

    # Webhook - routes to internal ALB with host header
    ingress_rule {
      hostname = "webhook.${local.domain}"
      path     = "^/github-webhook(/.*)?$"
      service  = "http://${local.alb_dns}:80"
      origin_request {
        http_host_header = "webhook.${local.domain}"
      }
    }

    # Webhook TEST - same routing for testing
    ingress_rule {
      hostname = "webhook-test.${local.domain}"
      path     = "^/github-webhook(/.*)?$"
      service  = "http://${local.alb_dns}:80"
      origin_request {
        http_host_header = "webhook.${local.domain}"
      }
    }

    # Catch-all (required)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# DNS records pointing to Tunnel (for test first, then production cutover)
resource "cloudflare_record" "jenkins_tunnel_test" {
  count = var.enable_tunnel_test ? 1 : 0

  zone_id = local.zone_id
  name    = "jenkins-test"
  content = "${cloudflare_tunnel.nameless.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true

  comment = "Jenkins test via Tunnel - managed by Terraform"
}

resource "cloudflare_record" "webhook_tunnel_test" {
  count = var.enable_tunnel_test ? 1 : 0

  zone_id = local.zone_id
  name    = "webhook-test"
  content = "${cloudflare_tunnel.nameless.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true

  comment = "Webhook test via Tunnel - managed by Terraform"
}

# -----------------------------------------------------------------------------
# Cloudflared ECS Service
# Runs cloudflared connector to establish tunnel from VPC to Cloudflare
# -----------------------------------------------------------------------------

# Get remote state for networking and ECS
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

data "aws_region" "current" {}

# IAM role for cloudflared task to read SSM
resource "aws_iam_role" "cloudflared_task" {
  name = "nameless-cloudflared-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudflared_ssm" {
  name = "cloudflared-ssm-access"
  role = aws_iam_role.cloudflared_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          aws_ssm_parameter.tunnel_token.arn
        ]
      }
    ]
  })
}

# Security group for cloudflared (needs outbound access only)
resource "aws_security_group" "cloudflared" {
  name        = "nameless-cloudflared-sg"
  description = "Security group for cloudflared tunnel connector"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  # Outbound - Allow all (needed for Cloudflare tunnel and ALB)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nameless-cloudflared-sg"
  }
}

# Task definition for cloudflared
resource "aws_ecs_task_definition" "cloudflared" {
  family                   = "nameless-cloudflared"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  execution_role_arn       = data.terraform_remote_state.ecs.outputs.task_execution_role_arn
  task_role_arn            = aws_iam_role.cloudflared_task.arn
  
  cpu    = 256
  memory = 256

  container_definitions = jsonencode([
    {
      name      = "cloudflared"
      image     = "cloudflare/cloudflared:latest"
      essential = true
      
      command = ["tunnel", "--no-autoupdate", "run"]

      secrets = [
        {
          name      = "TUNNEL_TOKEN"
          valueFrom = aws_ssm_parameter.tunnel_token.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/nameless-cloudflared"
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "cloudflared"
          "awslogs-create-group"  = "true"
        }
      }

      # Health check removed - cloudflared alpine image doesn't have pgrep
      # Tunnel health is monitored via Cloudflare API instead
    }
  ])

  tags = {
    Name = "nameless-cloudflared-task"
  }
}

# ECS Service for cloudflared
resource "aws_ecs_service" "cloudflared" {
  name            = "nameless-cloudflared"
  cluster         = data.terraform_remote_state.ecs.outputs.cluster_arn
  task_definition = aws_ecs_task_definition.cloudflared.arn
  desired_count   = 1

  # Pin to CI capacity provider (same as Jenkins)
  capacity_provider_strategy {
    capacity_provider = data.terraform_remote_state.ecs.outputs.ci_capacity_provider_name
    base              = 1
    weight            = 100
  }

  # Network configuration required for awsvpc mode
  network_configuration {
    subnets          = data.terraform_remote_state.network.outputs.private_subnet_ids
    security_groups  = [aws_security_group.cloudflared.id]
    assign_public_ip = false
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    Name = "nameless-cloudflared-service"
  }
}
