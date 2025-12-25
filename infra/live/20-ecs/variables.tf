# =============================================================================
# 20-ecs - Variables
# =============================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "nameless"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights (adds ~$3/month)"
  type        = bool
  default     = false
}

variable "ecs_instance_type" {
  description = "EC2 instance type for ECS cluster"
  type        = string
  default     = "t4g.small"  # ~$12/month, ARM-based, 2GB RAM
}

variable "ecs_ci_instance_type" {
  description = "EC2 instance type for CI capacity provider (Jenkins)"
  type        = string
  default     = "t4g.medium"  # ~$24/month, ARM-based, 4GB RAM (needed for Jenkins + JCasC)
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
