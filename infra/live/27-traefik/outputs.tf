# =============================================================================
# 27-traefik - Outputs
# =============================================================================

output "traefik_service_arn" {
  description = "ARN of the Traefik ECS service"
  value       = aws_ecs_service.traefik.id
}

output "traefik_service_name" {
  description = "Name of the Traefik ECS service"
  value       = aws_ecs_service.traefik.name
}

output "traefik_security_group_id" {
  description = "Security group ID for Traefik"
  value       = aws_security_group.traefik.id
}

output "traefik_dns_name" {
  description = "DNS name for Traefik via Cloud Map (traefik.nameless.local)"
  value       = "${aws_service_discovery_service.traefik.name}.${data.terraform_remote_state.network.outputs.service_discovery_namespace_name}"
}

output "traefik_task_role_arn" {
  description = "ARN of the Traefik task IAM role"
  value       = aws_iam_role.traefik_task.arn
}

output "traefik_log_group" {
  description = "CloudWatch log group for Traefik"
  value       = aws_cloudwatch_log_group.traefik.name
}

output "traefik_endpoint" {
  description = "Internal endpoint to reach Traefik (for cloudflared)"
  value       = "http://traefik.nameless.local:80"
}
