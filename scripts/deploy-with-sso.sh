#!/bin/bash
# Deploy Infrastructure with AWS SSO
# This script exports AWS SSO credentials and runs Terraform

set -e

echo "🔐 Setting up AWS SSO credentials for Terraform..."

# Extract SSO credentials and export as environment variables
# This allows Terraform to use them during backend initialization
AWS_CREDS=$(aws sts get-session-token --output json 2>/dev/null || aws sts get-caller-identity --output json)

# Get credentials from SSO using aws2-wrap or direct access
# First, let's try getting credentials directly from the CLI credential process
CRED_CACHE=$(aws configure get sso_start_url)

if [ ! -z "$CRED_CACHE" ]; then
    echo "📡 Using AWS SSO credentials..."
    export AWS_PROFILE=default
    export AWS_SDK_LOAD_CONFIG=1
    
    # Get temporary credentials and export them
    AWS_CREDS_JSON=$(python3 << 'EOF'
import json
import subprocess
import sys

try:
    # Get credentials using AWS CLI
    result = subprocess.run(
        ['aws', 'sts', 'get-caller-identity'],
        capture_output=True,
        text=True
    )
    
    if result.returncode == 0:
        # Now get the actual credentials from the credential provider
        creds_result = subprocess.run(
            ['aws', 'configure', 'get', 'sso_account_id'],
            capture_output=True,
            text=True
        )
        print("SSO_CONFIGURED")
    else:
        print("ERROR", file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    )
    
    if [ "$AWS_CREDS_JSON" == "SSO_CONFIGURED" ]; then
        echo "✅ SSO Session Active"
        export AWS_PROFILE=default
        export AWS_SDK_LOAD_CONFIG=1
    fi
fi

# Verify credentials work
echo "✅ AWS Account: $(aws sts get-caller-identity --query Account --output text)"
echo "✅ AWS User: $(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2)"
echo "✅ Using AWS Profile: $AWS_PROFILE"

# Change to dev environment
cd "$(dirname "$0")/../envs/dev"

echo ""
echo "🚀 Initializing Terraform..."
terraform init

echo ""
echo "📋 Planning infrastructure changes..."
terraform plan -out=tfplan

echo ""
echo "🎯 Applying infrastructure..."
terraform apply tfplan

echo ""
echo "✅ Infrastructure deployed successfully!"
echo ""
echo "📊 Outputs:"
terraform output

echo ""
echo "💡 Next steps:"
echo "1. Get ALB DNS name from outputs above"
echo "2. Configure Cloudflare DNS to point to ALB"
echo "3. Deploy Kubernetes applications"
