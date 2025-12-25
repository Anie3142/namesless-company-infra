# =============================================================================
# Outputs for Cloudflare Infrastructure
# =============================================================================

output "tunnel_id" {
  description = "Cloudflare Tunnel ID"
  value       = cloudflare_tunnel.nameless.id
}

output "tunnel_cname" {
  description = "Cloudflare Tunnel CNAME for DNS"
  value       = "${cloudflare_tunnel.nameless.id}.cfargotunnel.com"
}

output "tunnel_token_ssm_parameter" {
  description = "SSM Parameter name containing tunnel token"
  value       = aws_ssm_parameter.tunnel_token.name
}

output "jenkins_dns_record" {
  description = "Jenkins DNS record"
  value       = cloudflare_record.jenkins.hostname
}

output "webhook_dns_record" {
  description = "Webhook DNS record"
  value       = cloudflare_record.webhook.hostname
}

output "jenkins_test_url" {
  description = "Jenkins test URL via Tunnel (when enabled)"
  value       = var.enable_tunnel_test ? "https://jenkins-test.namelesscompany.cc" : "Tunnel test not enabled"
}

output "webhook_test_url" {
  description = "Webhook test URL via Tunnel (when enabled)"
  value       = var.enable_tunnel_test ? "https://webhook-test.namelesscompany.cc/github-webhook/" : "Tunnel test not enabled"
}

output "cloudflared_security_group_id" {
  description = "Security group ID for cloudflared tunnel connector"
  value       = aws_security_group.cloudflared.id
}

output "n8n_url" {
  description = "n8n URL via Tunnel"
  value       = "https://n8n.namelesscompany.cc"
}
