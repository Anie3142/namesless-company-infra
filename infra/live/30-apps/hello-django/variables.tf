# =============================================================================
# 30-apps/hello-django - Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "nameless"
}

variable "container_image" {
  description = "Docker image for hello-django (updated by CI/CD)"
  type        = string
  default     = "nginx:alpine"  # Placeholder until we build the real image
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
