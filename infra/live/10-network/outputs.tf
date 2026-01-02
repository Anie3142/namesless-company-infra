# =============================================================================
# 10-network - Outputs
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = module.networking.vpc_cidr
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.networking.private_subnet_ids
}

output "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  value       = module.networking.private_subnet_cidrs
}

output "nat_instance_id" {
  description = "ID of the NAT instance"
  value       = module.nat_instance.nat_instance_id
}

output "nat_public_ip" {
  description = "Public IP of the NAT instance"
  value       = module.nat_instance.nat_public_ip
}

output "azs" {
  description = "Availability zones used"
  value       = module.networking.azs
}

# Service Discovery outputs
output "service_discovery_namespace_id" {
  description = "ID of the Cloud Map service discovery namespace"
  value       = aws_service_discovery_private_dns_namespace.main.id
}

output "service_discovery_namespace_name" {
  description = "Name of the Cloud Map service discovery namespace"
  value       = aws_service_discovery_private_dns_namespace.main.name
}

output "service_discovery_jenkins_service_id" {
  description = "ARN of the Jenkins service discovery service"
  value       = aws_service_discovery_service.jenkins.arn
}

output "service_discovery_n8n_service_id" {
  description = "ARN of the n8n service discovery service"
  value       = aws_service_discovery_service.n8n.arn
}
