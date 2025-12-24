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
