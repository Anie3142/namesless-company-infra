# =============================================================================
# 25-cicd/jenkins - Jenkins CI/CD Controller
# Deploys Jenkins on ECS with EFS persistence
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
    key            = "live/25-cicd/jenkins/terraform.tfstate"
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
      Component   = "jenkins"
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

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# EFS for Jenkins Home (persistent storage)
# -----------------------------------------------------------------------------
resource "aws_efs_file_system" "jenkins" {
  creation_token = "${var.project_name}-jenkins-efs"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name = "${var.project_name}-jenkins-efs"
  }
}

# EFS Mount Targets in private subnets
resource "aws_efs_mount_target" "jenkins" {
  for_each = toset(data.terraform_remote_state.network.outputs.private_subnet_ids)

  file_system_id  = aws_efs_file_system.jenkins.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

# Security Group for EFS
resource "aws_security_group" "efs" {
  name        = "${var.project_name}-jenkins-efs-sg"
  description = "Security group for Jenkins EFS"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  # Allow NFS from CI ECS instances
  ingress {
    description     = "NFS from CI ECS instances"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.ecs.outputs.ci_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-jenkins-efs-sg"
  }
}

# -----------------------------------------------------------------------------
# Task Role for Jenkins (for EFS access via IAM)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "jenkins_task" {
  name = "${var.project_name}-jenkins-task-role"

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
    Name = "${var.project_name}-jenkins-task-role"
  }
}

# Allow Jenkins task to access EFS
resource "aws_iam_role_policy" "jenkins_efs" {
  name = "${var.project_name}-jenkins-efs-policy"
  role = aws_iam_role.jenkins_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.jenkins.arn
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessPointArn" = aws_efs_access_point.jenkins.arn
          }
        }
      }
    ]
  })
}

# EFS Access Point for Jenkins
resource "aws_efs_access_point" "jenkins" {
  file_system_id = aws_efs_file_system.jenkins.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/jenkins_home"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name = "${var.project_name}-jenkins-access-point"
  }
}

# -----------------------------------------------------------------------------
# SSM Read Policy for Task Execution Role (needed for secrets)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "jenkins_ssm_secrets" {
  name = "${var.project_name}-jenkins-ssm-secrets"
  role = element(split("/", data.terraform_remote_state.ecs.outputs.task_execution_role_arn), length(split("/", data.terraform_remote_state.ecs.outputs.task_execution_role_arn)) - 1)

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/nameless/jenkins/*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Jenkins Task Definition
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "jenkins" {
  family                   = "${var.project_name}-jenkins"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  execution_role_arn       = data.terraform_remote_state.ecs.outputs.task_execution_role_arn
  task_role_arn            = aws_iam_role.jenkins_task.arn
  
  cpu    = 1024  # 1 vCPU
  memory = 1536  # 1.5GB

  volume {
    name = "jenkins_home"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.jenkins.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.jenkins.id
        iam             = "ENABLED"
      }
    }
  }

  # Docker socket for Docker-in-Docker builds
  volume {
    name      = "docker_socket"
    host_path = "/var/run/docker.sock"
  }

  container_definitions = jsonencode([
    {
      name      = "jenkins"
      # Custom Jenkins image with JCasC + plugins pre-installed
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/nameless-jenkins:latest"
      essential = true
      
      # Run as root to access Docker socket
      # The Docker socket on the host is owned by root:docker (GID varies)
      user      = "0:0"
      
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080  # Static port - used by cloudflared via service discovery
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "jenkins_home"
          containerPath = "/var/jenkins_home"
          readOnly      = false
        },
        {
          sourceVolume  = "docker_socket"
          containerPath = "/var/run/docker.sock"
          readOnly      = false
        }
      ]

      environment = [
        {
          name  = "JAVA_OPTS"
          value = "-Djenkins.install.runSetupWizard=false -Xmx1g"
        }
      ]

      # No secrets needed for vanilla Jenkins

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}-jenkins"
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "jenkins"
          "awslogs-create-group"  = "true"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/login || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 120  # Jenkins takes time to start
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-jenkins-task"
  }
}

# -----------------------------------------------------------------------------
# ALB REMOVED - Traffic now routes via Cloudflare Tunnel → Service Discovery
# Target Group, Listener Rules deleted - saves ~$16/month!
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Jenkins ECS Service (pinned to CI capacity provider)
# No ALB - accessed via Cloudflare Tunnel → jenkins.nameless.local:8080
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "jenkins" {
  name            = "${var.project_name}-jenkins"
  cluster         = data.terraform_remote_state.ecs.outputs.cluster_arn
  task_definition = aws_ecs_task_definition.jenkins.arn
  desired_count   = 1

  # Pin to CI capacity provider
  capacity_provider_strategy {
    capacity_provider = data.terraform_remote_state.ecs.outputs.ci_capacity_provider_name
    base              = 1
    weight            = 100
  }

  # NO load_balancer block - traffic via tunnel

  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  # Don't recreate service if task definition changes
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    Name = "${var.project_name}-jenkins-service"
  }

  depends_on = [
    aws_efs_mount_target.jenkins
  ]
}
