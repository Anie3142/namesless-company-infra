# =============================================================================
# 15-database - Variables
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

# -----------------------------------------------------------------------------
# Database Configuration
# -----------------------------------------------------------------------------

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"  # ~$12/month, upgrade to db.t4g.small if needed
}

variable "db_allocated_storage" {
  description = "Initial storage in GB"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Max storage for autoscaling"
  type        = number
  default     = 50
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# App-Specific Databases
# -----------------------------------------------------------------------------

variable "app_databases" {
  description = "Map of applications that need database access. Each app will get an SSM parameter with its DATABASE_URL"
  type = map(object({
    database_name = string
  }))
  default = {
    "personal-finance" = {
      database_name = "personal_finance"
    }
    "hello-django" = {
      database_name = "hello_django"
    }
  }
}
