# =============================================================================
# 27-traefik - Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "traefik_task_count" {
  description = "Number of Traefik tasks (2 recommended for HA)"
  type        = number
  default     = 2
}
