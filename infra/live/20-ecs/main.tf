# =============================================================================
# 20-ecs - ECS Platform Infrastructure
# Creates ECS cluster with EC2 Capacity Provider, ALB, ECR, and IAM roles
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
    key            = "live/20-ecs/terraform.tfstate"
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
# Cloudflare IP Ranges (for ALB Security Group)
# Source: https://www.cloudflare.com/ips/
# -----------------------------------------------------------------------------
locals {
  cloudflare_ipv4_cidrs = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22"
  ]
  
  # NAT instance public IP - needed for Cloudflare Tunnel (cloudflared → NAT → ALB)
  nat_public_ip_cidr = "${data.terraform_remote_state.network.outputs.nat_public_ip}/32"
  
  # Combined allowed CIDRs: Cloudflare + NAT IP for tunnel
  alb_allowed_cidrs = concat(local.cloudflare_ipv4_cidrs, [local.nat_public_ip_cidr])
}

# -----------------------------------------------------------------------------
# ALB Module
# -----------------------------------------------------------------------------
module "alb" {
  source = "../../modules/alb"

  project_name      = var.project_name
  vpc_id            = data.terraform_remote_state.network.outputs.vpc_id
  public_subnet_ids = data.terraform_remote_state.network.outputs.public_subnet_ids
  
  # SECURITY HARDENING: Only allow traffic from Cloudflare + NAT (for Cloudflare Tunnel)
  allowed_cidr_blocks = local.alb_allowed_cidrs

  tags = var.tags
}

# -----------------------------------------------------------------------------
# ECS EC2 Cluster Module - Apps Capacity Provider (cp-apps)
# For running application workloads (n8n, hello-django, etc.)
# -----------------------------------------------------------------------------
module "ecs_ec2_cluster" {
  source = "../../modules/ecs-ec2-cluster"

  project_name       = var.project_name
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  
  # ALB SG for inbound traffic
  alb_security_group_id = module.alb.alb_security_group_id

  # EC2 Configuration
  instance_type     = var.ecs_instance_type
  min_instances     = 1
  max_instances     = 2
  desired_instances = 1

  enable_container_insights = var.enable_container_insights

  tags = var.tags
}

# -----------------------------------------------------------------------------
# CI Capacity Provider (cp-ci) - INLINE
# For Jenkins controller and build workloads - separate from apps
# -----------------------------------------------------------------------------

# Get ECS AMI for CI instances
data "aws_ssm_parameter" "ecs_ami_ci" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
}

# Security Group for CI ECS instances
resource "aws_security_group" "ecs_ci" {
  name        = "${var.project_name}-ecs-ci-sg"
  description = "Security group for ECS CI instances"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  # Allow inbound from ALB
  ingress {
    description     = "Allow from ALB"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [module.alb.alb_security_group_id]
  }

  # All outbound (for NAT)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-ecs-ci-sg"
  })
}

# Launch Template for CI instances
resource "aws_launch_template" "ecs_ci" {
  name_prefix   = "${var.project_name}-ecs-ci-"
  image_id      = data.aws_ssm_parameter.ecs_ami_ci.value
  instance_type = var.ecs_instance_type  # Same as apps for now

  iam_instance_profile {
    arn = module.ecs_ec2_cluster.ecs_instance_profile_arn
  }

  vpc_security_group_ids = [aws_security_group.ecs_ci.id]

  # User data to join ECS cluster
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "ECS_CLUSTER=${module.ecs_ec2_cluster.cluster_name}" >> /etc/ecs/ecs.config
    echo "ECS_ENABLE_CONTAINER_METADATA=true" >> /etc/ecs/ecs.config
    EOF
  )

  monitoring {
    enabled = false
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.project_name}-ecs-ci-instance"
    })
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-ecs-ci-launch-template"
  })
}

# Auto Scaling Group for CI
resource "aws_autoscaling_group" "ecs_ci" {
  name                = "${var.project_name}-ecs-ci-asg"
  vpc_zone_identifier = data.terraform_remote_state.network.outputs.private_subnet_ids
  
  min_size         = 0  # Start with 0, will scale up when Jenkins deployed
  max_size         = 2
  desired_capacity = 0  # Start with 0

  protect_from_scale_in = true

  launch_template {
    id      = aws_launch_template.ecs_ci.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-ecs-ci-instance"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# CI Capacity Provider
resource "aws_ecs_capacity_provider" "ci" {
  name = "${var.project_name}-ci-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_ci.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      maximum_scaling_step_size = 2
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-ci-capacity-provider"
  })
}

# Update cluster to use BOTH capacity providers
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = module.ecs_ec2_cluster.cluster_name

  capacity_providers = [
    module.ecs_ec2_cluster.capacity_provider_name,  # cp-apps
    aws_ecs_capacity_provider.ci.name                # cp-ci
  ]

  # Default to apps capacity provider
  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = module.ecs_ec2_cluster.capacity_provider_name
  }
}

# -----------------------------------------------------------------------------
# ECR Repository for n8n
# -----------------------------------------------------------------------------
module "ecr_n8n" {
  source = "../../modules/ecr"

  repository_name = "${var.project_name}-n8n"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Get current AWS account info for SSM ARN construction
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# IAM - ECS Task Execution Role
# -----------------------------------------------------------------------------
module "ecs_task_execution_role" {
  source = "../../modules/iam/ecs-task-execution"

  project_name = var.project_name

  # Enable SSM Parameter Store access for secrets
  enable_secrets_access = true
  
  # Allow access to all parameters under /nameless/*
  ssm_parameter_arns = [
    "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*"
  ]
  
  # No Secrets Manager needed (using free SSM Parameter Store)
  secrets_manager_arns = []

  tags = var.tags
}
