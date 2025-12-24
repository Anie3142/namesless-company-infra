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

  container_definitions = jsonencode([
    {
      name      = "jenkins"
      image     = "jenkins/jenkins:lts-jdk17"
      essential = true
      
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 0  # Dynamic port mapping
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "jenkins_home"
          containerPath = "/var/jenkins_home"
          readOnly      = false
        }
      ]

      environment = [
        {
          name  = "JAVA_OPTS"
          value = "-Djenkins.install.runSetupWizard=false -Xmx1g"
        }
      ]

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
# Target Group for Jenkins
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "jenkins" {
  name                 = "${var.project_name}-jenkins-tg"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = data.terraform_remote_state.network.outputs.vpc_id
  target_type          = "instance"
  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200,403"  # 403 is OK - Jenkins login page
    path                = "/login"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 10
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-jenkins-tg"
  }
}

# -----------------------------------------------------------------------------
# ALB Listener Rule for jenkins.namelesscompany.cc
# -----------------------------------------------------------------------------
resource "aws_lb_listener_rule" "jenkins" {
  listener_arn = data.terraform_remote_state.ecs.outputs.http_listener_arn
  priority     = 90  # Lower priority = higher precedence

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }

  condition {
    host_header {
      values = [var.jenkins_domain]
    }
  }

  tags = {
    Name = "${var.project_name}-jenkins-rule"
  }
}

# -----------------------------------------------------------------------------
# ALB Listener Rule for webhook.namelesscompany.cc (GitHub webhooks)
# -----------------------------------------------------------------------------
resource "aws_lb_listener_rule" "webhook" {
  listener_arn = data.terraform_remote_state.ecs.outputs.http_listener_arn
  priority     = 91

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }

  condition {
    host_header {
      values = [var.webhook_domain]
    }
  }

  # Only allow /github-webhook/ path
  condition {
    path_pattern {
      values = ["/github-webhook/*"]
    }
  }

  tags = {
    Name = "${var.project_name}-webhook-rule"
  }
}

# -----------------------------------------------------------------------------
# Jenkins ECS Service (pinned to CI capacity provider)
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

  load_balancer {
    target_group_arn = aws_lb_target_group.jenkins.arn
    container_name   = "jenkins"
    container_port   = 8080
  }

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
    aws_efs_mount_target.jenkins,
    aws_lb_listener_rule.jenkins
  ]
}
