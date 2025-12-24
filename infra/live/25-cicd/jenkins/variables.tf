# =============================================================================
# Variables for Jenkins CI/CD
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "nameless"
}

variable "jenkins_domain" {
  description = "Domain for Jenkins"
  type        = string
  default     = "jenkins.namelesscompany.cc"
}

variable "webhook_domain" {
  description = "Domain for GitHub webhooks"
  type        = string
  default     = "webhook.namelesscompany.cc"
}
