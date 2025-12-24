# =============================================================================
# 20-ecs - Outputs
# =============================================================================

# ALB Outputs
output "alb_dns_name" {
  description = "DNS name of the ALB - Use this for Cloudflare CNAME"
  value       = module.alb.alb_dns_name
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = module.alb.alb_arn
}

output "alb_zone_id" {
  description = "Zone ID of the ALB (for Route53)"
  value       = module.alb.alb_zone_id
}

output "alb_security_group_id" {
  description = "Security group ID of the ALB"
  value       = module.alb.alb_security_group_id
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener"
  value       = module.alb.http_listener_arn
}

# ECS Cluster Outputs
output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs_ec2_cluster.cluster_arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_ec2_cluster.cluster_name
}

# Apps Capacity Provider (for application workloads)
output "capacity_provider_name" {
  description = "Apps EC2 capacity provider name (for application workloads)"
  value       = module.ecs_ec2_cluster.capacity_provider_name
}

output "apps_capacity_provider_name" {
  description = "Apps EC2 capacity provider name (alias)"
  value       = module.ecs_ec2_cluster.capacity_provider_name
}

output "ecs_instances_security_group_id" {
  description = "Security group ID for ECS EC2 instances (apps)"
  value       = module.ecs_ec2_cluster.ecs_instances_security_group_id
}

# CI Capacity Provider (for Jenkins and build workloads)
output "ci_capacity_provider_name" {
  description = "CI EC2 capacity provider name (for Jenkins/builds)"
  value       = aws_ecs_capacity_provider.ci.name
}

output "ci_security_group_id" {
  description = "Security group ID for CI ECS instances"
  value       = aws_security_group.ecs_ci.id
}

# ECR Outputs
output "ecr_n8n_repository_url" {
  description = "URL of the n8n ECR repository"
  value       = module.ecr_n8n.repository_url
}

# IAM Outputs
output "task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = module.ecs_task_execution_role.role_arn
}
