# =============================================================================
# Outputs for Jenkins CI/CD
# =============================================================================

output "jenkins_url" {
  description = "Jenkins URL"
  value       = "http://${var.jenkins_domain}"
}

output "webhook_url" {
  description = "GitHub webhook URL"
  value       = "http://${var.webhook_domain}/github-webhook/"
}

output "efs_file_system_id" {
  description = "EFS file system ID for Jenkins"
  value       = aws_efs_file_system.jenkins.id
}

output "jenkins_target_group_arn" {
  description = "Jenkins target group ARN"
  value       = aws_lb_target_group.jenkins.arn
}

output "jenkins_service_name" {
  description = "Jenkins ECS service name"
  value       = aws_ecs_service.jenkins.name
}
