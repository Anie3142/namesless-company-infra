# =============================================================================
# 30-apps/hello-django - Outputs
# =============================================================================

output "service_arn" {
  description = "ARN of the ECS service"
  value       = module.hello_django_service.service_arn
}

output "service_name" {
  description = "Name of the ECS service"
  value       = module.hello_django_service.service_name
}

output "service_discovery_dns_name" {
  description = "Service Discovery DNS name (for cloudflared routing)"
  value       = module.hello_django_service.service_discovery_dns_name
}

output "service_discovery_service_id" {
  description = "Cloud Map Service ID"
  value       = module.hello_django_service.service_discovery_service_id
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = module.hello_django_service.log_group_name
}

output "tunnel_url" {
  description = "URL to access the service via Cloudflare Tunnel"
  value       = "https://api.namelesscompany.cc"
}
