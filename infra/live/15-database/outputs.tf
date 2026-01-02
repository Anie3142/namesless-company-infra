# =============================================================================
# 15-database - Outputs
# =============================================================================

output "db_endpoint" {
  description = "RDS endpoint (hostname:port)"
  value       = module.postgres.endpoint
}

output "db_address" {
  description = "RDS hostname"
  value       = module.postgres.address
}

output "db_port" {
  description = "RDS port"
  value       = module.postgres.port
}

output "db_name" {
  description = "Database name"
  value       = module.postgres.database_name
}

output "db_username" {
  description = "Database username"
  value       = module.postgres.username
  sensitive   = true
}

output "db_security_group_id" {
  description = "RDS security group ID"
  value       = module.postgres.security_group_id
}

output "db_password_ssm_parameter" {
  description = "SSM parameter name for database password"
  value       = aws_ssm_parameter.db_password.name
}

output "n8n_encryption_key_ssm_parameter" {
  description = "SSM parameter name for n8n encryption key"
  value       = aws_ssm_parameter.n8n_encryption_key.name
}

# Connection info for apps
output "connection_info" {
  description = "Database connection information"
  value = {
    host     = module.postgres.address
    port     = module.postgres.port
    database = module.postgres.database_name
    username = module.postgres.username
    password_ssm = aws_ssm_parameter.db_password.name
  }
  sensitive = true
}

# App-specific DATABASE_URL SSM parameters
output "app_database_url_ssm_parameters" {
  description = "SSM parameter names for each app's DATABASE_URL"
  value = {
    for app_name, param in aws_ssm_parameter.app_database_urls : app_name => param.name
  }
}

output "app_database_url_ssm_arns" {
  description = "SSM parameter ARNs for each app's DATABASE_URL (use in ECS task secrets)"
  value = {
    for app_name, param in aws_ssm_parameter.app_database_urls : app_name => param.arn
  }
}

output "n8n_database_url_ssm_parameter" {
  description = "SSM parameter name for n8n DATABASE_URL"
  value       = aws_ssm_parameter.n8n_database_url.name
}

output "n8n_database_url_ssm_arn" {
  description = "SSM parameter ARN for n8n DATABASE_URL"
  value       = aws_ssm_parameter.n8n_database_url.arn
}
