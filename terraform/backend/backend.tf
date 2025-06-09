# Backend configuration for remote state
# This file will be used after initial bootstrap

terraform {
  backend "s3" {
    bucket         = "terraform-state-kops-852a22b5"
    key            = "backend/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
