output "terraform_state_bucket" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.buckets["terraform-state"].bucket
}

output "terraform_state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.buckets["terraform-state"].arn
}

output "kops_state_bucket" {
  description = "Name of the S3 bucket for kOps state"
  value       = aws_s3_bucket.buckets["kops-state"].bucket
}

output "kops_state_bucket_arn" {
  description = "ARN of the S3 bucket for kOps state"
  value       = aws_s3_bucket.buckets["kops-state"].arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "all_buckets" {
  description = "All S3 buckets created with their purposes"
  value = {
    for key, bucket in aws_s3_bucket.buckets : key => {
      name    = bucket.bucket
      arn     = bucket.arn
      purpose = local.buckets[key].purpose
    }
  }
}

output "backend_config" {
  description = "Backend configuration for use in other Terraform configurations"
  value = {
    bucket         = aws_s3_bucket.buckets["terraform-state"].bucket
    key            = "terraform.tfstate"
    region         = var.aws_region
    dynamodb_table = aws_dynamodb_table.terraform_locks.name
    encrypt        = true
  }
}

output "cost_summary" {
  description = "Estimated monthly costs for the backend infrastructure"
  value = {
    s3_storage_gb_month     = "~0.001 (state files <1MB)"
    s3_requests_month       = "~$0.001 (minimal operations)"
    dynamodb_month          = "~$0.01 (state locking only)"
    total_estimated_month   = "~$0.05"
    note                    = "Costs scale with usage, lifecycle rules minimize storage costs"
  }
}
