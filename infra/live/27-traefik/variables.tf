# =============================================================================
# 27-traefik - Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "traefik_task_count" {
  description = "Number of Traefik tasks to run (limited by ENI capacity on small instances)"
  type        = number
  default     = 1  # Reduced to 1 due to ENI limits on t4g.small instances
}
