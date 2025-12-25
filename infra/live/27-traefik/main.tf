# =============================================================================
# 27-traefik - Traefik Reverse Proxy for Dynamic App Routing
# =============================================================================
# This deploys Traefik as an ECS service that automatically discovers and
# routes traffic to apps based on Docker labels in their ECS task definitions.
#
# Key features:
# - ECS provider (not Docker provider) for auto-discovery
# - exposedByDefault=false for security
# - 2 tasks for high availability
# - Cloud Map service discovery: traefik.nameless.local
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
    key            = "live/27-traefik/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "nameless-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# Data Sources - Remote State
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

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  name_prefix   = "nameless"
  cluster_name  = data.terraform_remote_state.ecs.outputs.cluster_name
  cluster_arn   = data.terraform_remote_state.ecs.outputs.cluster_arn
  vpc_id        = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr      = data.terraform_remote_state.network.outputs.vpc_cidr
  namespace_id  = data.terraform_remote_state.network.outputs.service_discovery_namespace_id
  subnet_ids    = data.terraform_remote_state.network.outputs.private_subnet_ids
}

# -----------------------------------------------------------------------------
# Cloud Map Service Discovery - traefik.nameless.local
# -----------------------------------------------------------------------------

resource "aws_service_discovery_service" "traefik" {
  name = "traefik"

  dns_config {
    namespace_id   = local.namespace_id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = {
    Name      = "${local.name_prefix}-traefik-discovery"
    ManagedBy = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for Traefik Task - Needs ECS Read Permissions
# -----------------------------------------------------------------------------

resource "aws_iam_role" "traefik_task" {
  name = "${local.name_prefix}-traefik-task-role"

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

  tags = {
    Name      = "${local.name_prefix}-traefik-task-role"
    ManagedBy = "Terraform"
  }
}

# ECS read permissions for Traefik ECS provider
resource "aws_iam_role_policy" "traefik_ecs_read" {
  name = "traefik-ecs-read"
  role = aws_iam_role.traefik_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:ListClusters",
          "ecs:DescribeClusters",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:DescribeTaskDefinition",
          "ecs:ListServices",
          "ecs:DescribeServices",
          "ecs:ListContainerInstances",
          "ecs:DescribeContainerInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Security Group for Traefik
# -----------------------------------------------------------------------------

resource "aws_security_group" "traefik" {
  name        = "${local.name_prefix}-traefik-sg"
  description = "Security group for Traefik reverse proxy"
  vpc_id      = local.vpc_id

  # HTTP from within VPC (cloudflared connects here)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
    description = "HTTP from VPC"
  }

  # Traefik dashboard (optional, internal only)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
    description = "Traefik dashboard from VPC"
  }

  # Outbound - Allow all (needed to reach app containers)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name      = "${local.name_prefix}-traefik-sg"
    ManagedBy = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# SSM Parameter for Traefik Static Configuration
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "traefik_config" {
  name        = "/nameless/traefik/static-config"
  description = "Traefik static configuration (YAML)"
  type        = "String"
  value       = yamlencode({
    # Entry points
    entryPoints = {
      web = {
        address = ":80"
      }
      traefik = {
        address = ":8080"
      }
    }
    
    # API and Dashboard (internal only)
    api = {
      dashboard = true
      insecure  = true  # Only accessible within VPC
    }
    
    # ECS Provider - Auto-discovers services
    providers = {
      ecs = {
        clusters = [local.cluster_name]
        region   = data.aws_region.current.name
        exposedByDefault  = false  # CRITICAL: Only route services with traefik.enable=true
        autoDiscoverClusters = false
        refreshSeconds = 15
      }
    }
    
    # Access logging
    accessLog = {}
    
    # Logging
    log = {
      level = "INFO"
    }
  })

  tags = {
    Name      = "${local.name_prefix}-traefik-config"
    ManagedBy = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# ECS Task Definition for Traefik
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "traefik" {
  family                   = "${local.name_prefix}-traefik"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  execution_role_arn       = data.terraform_remote_state.ecs.outputs.task_execution_role_arn
  task_role_arn            = aws_iam_role.traefik_task.arn

  # Traefik is lightweight
  cpu    = 256
  memory = 256

  container_definitions = jsonencode([
    {
      name      = "traefik"
      image     = "traefik:v3.2"  # Latest stable v3
      essential = true

      # Pass config via command line (reads from SSM would need init container)
      command = [
        "--entrypoints.web.address=:80",
        "--entrypoints.traefik.address=:8080",
        "--api.dashboard=true",
        "--api.insecure=true",
        "--providers.ecs.clusters=${local.cluster_name}",
        "--providers.ecs.region=${data.aws_region.current.name}",
        "--providers.ecs.exposedByDefault=false",
        "--providers.ecs.autoDiscoverClusters=false",
        "--providers.ecs.refreshSeconds=15",
        "--accesslog=true",
        "--log.level=INFO"
      ]

      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        },
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      # Health check
      healthCheck = {
        command     = ["CMD", "traefik", "healthcheck"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${local.name_prefix}-traefik"
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "traefik"
          "awslogs-create-group"  = "true"
        }
      }
    }
  ])

  tags = {
    Name      = "${local.name_prefix}-traefik-task"
    ManagedBy = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# ECS Service for Traefik (2 tasks for HA)
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "traefik" {
  name            = "${local.name_prefix}-traefik"
  cluster         = local.cluster_arn
  task_definition = aws_ecs_task_definition.traefik.arn
  desired_count   = var.traefik_task_count

  # Use apps capacity provider (runs on same instances as apps)
  capacity_provider_strategy {
    capacity_provider = data.terraform_remote_state.ecs.outputs.apps_capacity_provider_name
    base              = 1
    weight            = 100
  }

  # Network configuration (awsvpc mode)
  network_configuration {
    subnets          = local.subnet_ids
    security_groups  = [aws_security_group.traefik.id]
    assign_public_ip = false
  }

  # Service Discovery Registration
  service_registries {
    registry_arn = aws_service_discovery_service.traefik.arn
  }

  # Deployment settings
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  # Enable deployment circuit breaker
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Don't redeploy when task definition changes outside Terraform
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    Name      = "${local.name_prefix}-traefik-service"
    ManagedBy = "Terraform"
  }

  depends_on = [
    aws_service_discovery_service.traefik,
    aws_iam_role_policy.traefik_ecs_read
  ]
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for Traefik
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "traefik" {
  name              = "/ecs/${local.name_prefix}-traefik"
  retention_in_days = 14

  tags = {
    Name      = "${local.name_prefix}-traefik-logs"
    ManagedBy = "Terraform"
  }
}
