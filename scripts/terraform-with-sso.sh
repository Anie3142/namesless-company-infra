#!/bin/bash

# Script to run Terraform with AWS SSO credentials
# This extracts the temporary credentials from AWS SSO and sets them as environment variables

set -e

PROFILE=${1:-default}

echo "Getting AWS SSO credentials for profile: $PROFILE"

# Get the credentials from AWS CLI cache
CREDENTIALS=$(aws sts get-caller-identity --profile $PROFILE --output json 2>/dev/null || {
    echo "Error: Unable to get credentials. Please run 'aws sso login --profile $PROFILE' first"
    exit 1
})

echo "Successfully authenticated as: $(echo $CREDENTIALS | jq -r '.Arn')"

# Extract credentials from the SSO cache
AWS_CREDS_FILE=$(find ~/.aws/sso/cache -name "*.json" -exec grep -l "$(aws configure get sso_account_id --profile $PROFILE)" {} \; | head -1)

if [ -z "$AWS_CREDS_FILE" ]; then
    echo "Error: Could not find SSO credentials cache file"
    exit 1
fi

export AWS_ACCESS_KEY_ID=$(jq -r '.accessKeyId' "$AWS_CREDS_FILE")
export AWS_SECRET_ACCESS_KEY=$(jq -r '.secretAccessKey' "$AWS_CREDS_FILE")
export AWS_SESSION_TOKEN=$(jq -r '.sessionToken' "$AWS_CREDS_FILE")
export AWS_DEFAULT_REGION=$(aws configure get region --profile $PROFILE)

echo "Running Terraform with SSO credentials..."
terraform "$@"
