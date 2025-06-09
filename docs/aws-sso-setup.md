# AWS IAM Identity Center Setup Guide (Single Account)

## Prerequisites
- AWS Root account with MFA (YubiKey) enabled
- Access to AWS Console
- Single AWS account (no Organizations required)

## Step 1: Enable IAM Identity Center
1. Log into AWS Console as root user
2. Navigate to **IAM Identity Center** service (formerly AWS SSO)
3. Choose "Enable IAM Identity Center"
4. Select "Identity Center directory" (for single account setup)
5. Choose your region: **us-east-1** (for cost optimization)

## Step 2: Create DevOpsAdmin Group
1. In IAM Identity Center Console → Groups → Create group
2. Group name: `DevOpsAdmin`
3. Description: `DevOps administrators with full AWS access`

## Step 3: Create Your User
1. In IAM Identity Center Console → Users → Add user
2. Fill in your details (use your email as username)
3. Set a temporary password (you'll change it on first login)
4. Add to `DevOpsAdmin` group

## Step 4: Create Permission Set
1. In IAM Identity Center Console → Permission sets → Create permission set
2. Choose "Predefined permission set"
3. Select `AdministratorAccess`
4. Name: `AdminCLI`
5. Description: `Full administrative access for CLI/Terraform`
6. Session duration: 4 hours (balance between security and convenience)

## Step 5: Assign Permission Set to Your Account
1. In IAM Identity Center Console → AWS accounts
2. Select your current AWS account
3. Click "Assign users or groups"
4. Select `DevOpsAdmin` group
5. Select `AdminCLI` permission set
6. Click "Submit"

## Step 6: Get Your Access Portal URL
1. In IAM Identity Center Console → Dashboard
2. Copy the "AWS access portal URL" (looks like: https://d-xxxxxxxxxx.awsapps.com/start)
3. Save this URL - you'll need it for CLI configuration

## Step 7: Configure AWS CLI
Run the following command:
```bash
aws configure sso
```

Follow the prompts:
- **SSO session name**: `main`
- **SSO start URL**: (paste the URL from Step 6)
- **SSO region**: `us-east-1`
- **SSO registration scopes**: `sso:account:access` (default)
- **CLI default client region**: `us-east-1`
- **CLI default output format**: `json`
- **CLI profile name**: `default`

## Step 8: Login and Test Access
```bash
# Login to SSO session
aws sso login --profile default

# Test access
aws sts get-caller-identity --profile default
```

This should return your user details without errors.

## Step 9: Set Environment Variable (Optional)
Add to your shell profile (~/.zshrc or ~/.bash_profile):
```bash
export AWS_PROFILE=default
```

This ensures Terraform uses your SSO profile by default.
