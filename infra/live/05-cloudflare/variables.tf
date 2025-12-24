# =============================================================================
# Variables for Cloudflare Infrastructure
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "alb_dns_name" {
  description = "ALB DNS name (current origin before tunnel migration)"
  type        = string
  default     = "nameless-alb-922248069.us-east-1.elb.amazonaws.com"
}

variable "allowed_emails" {
  description = "List of emails allowed to access Jenkins via Cloudflare Access"
  type        = list(string)
  default     = ["aniebiet.ccie@gmail.com"]
}

variable "enable_tunnel_test" {
  description = "Enable test DNS records pointing to tunnel (for parallel testing)"
  type        = bool
  default     = false
}

variable "enable_tunnel_production" {
  description = "Switch production DNS to tunnel (final cutover)"
  type        = bool
  default     = false
}
