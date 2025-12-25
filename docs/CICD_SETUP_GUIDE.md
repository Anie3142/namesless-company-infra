# 🚀 CI/CD Setup Guide

## Overview

This guide covers setting up the complete CI/CD pipeline for Nameless Company infrastructure using:
- **Jenkins** with Configuration as Code (JCasC)
- **GitHub Webhooks** for automated builds
- **hello-django** demo app to test the full flow

---

## 📋 Prerequisites

Before starting:
- [x] Jenkins running at https://jenkins.namelesscompany.cc
- [x] Cloudflare Tunnel configured (webhook.namelesscompany.cc)
- [x] Service Discovery configured (nameless.local)
- [ ] Create hello-django repo on GitHub
- [ ] Store secrets in AWS SSM

---

## 1️⃣ Create GitHub OAuth App (for Jenkins login)

**GitHub OAuth allows you to login to Jenkins with your GitHub account - no passwords needed!**

### Step 1: Create OAuth App on GitHub
1. Go to https://github.com/settings/developers
2. Click **"New OAuth App"**
3. Fill in:
   - **Application name**: `Nameless Jenkins`
   - **Homepage URL**: `https://jenkins.namelesscompany.cc`
   - **Authorization callback URL**: `https://jenkins.namelesscompany.cc/securityRealm/finishLogin`
4. Click **"Register application"**
5. Copy the **Client ID**
6. Click **"Generate a new client secret"** and copy it

### Step 2: Store Secrets in SSM

```bash
# Store GitHub OAuth Client ID
aws ssm put-parameter \
  --name "/nameless/jenkins/github-oauth-client-id" \
  --value "YOUR_CLIENT_ID_HERE" \
  --type SecureString \
  --overwrite

# Store GitHub OAuth Client Secret
aws ssm put-parameter \
  --name "/nameless/jenkins/github-oauth-client-secret" \
  --value "YOUR_CLIENT_SECRET_HERE" \
  --type SecureString \
  --overwrite

# Store GitHub Personal Access Token (PAT) for API access
# Go to GitHub → Settings → Developer Settings → Personal Access Tokens → Tokens (classic)
# Create token with: repo, admin:repo_hook, workflow scopes
aws ssm put-parameter \
  --name "/nameless/github/token" \
  --value "ghp_xxxxxxxxxxxx" \
  --type SecureString \
  --overwrite

# Store GitHub webhook secret (generate a random string)
aws ssm put-parameter \
  --name "/nameless/github/webhook-secret" \
  --value "$(openssl rand -hex 32)" \
  --type SecureString \
  --overwrite
```

---

## 2️⃣ Build and Push Custom Jenkins Image

```bash
cd infra/live/25-cicd/jenkins/docker

# Get ECR login
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 975049891041.dkr.ecr.us-east-1.amazonaws.com

# Build the image
docker build -t nameless-jenkins:latest .

# Tag for ECR
docker tag nameless-jenkins:latest 975049891041.dkr.ecr.us-east-1.amazonaws.com/nameless-jenkins:latest

# Push to ECR
docker push 975049891041.dkr.ecr.us-east-1.amazonaws.com/nameless-jenkins:latest
```

---

## 3️⃣ Update Jenkins ECS Service to Use Custom Image

Update the Jenkins task definition in `infra/live/25-cicd/jenkins/main.tf` to:
1. Use the new ECR image
2. Add environment variables from SSM for GitHub OAuth

```hcl
# Add to container definition secrets:
secrets = {
  # GitHub OAuth (for login)
  "GITHUB_OAUTH_CLIENT_ID"     = "arn:aws:ssm:us-east-1:975049891041:parameter/nameless/jenkins/github-oauth-client-id"
  "GITHUB_OAUTH_CLIENT_SECRET" = "arn:aws:ssm:us-east-1:975049891041:parameter/nameless/jenkins/github-oauth-client-secret"
  
  # GitHub PAT (for API access, cloning repos)
  "GITHUB_TOKEN" = "arn:aws:ssm:us-east-1:975049891041:parameter/nameless/github/token"
}
```

**Note:** With GitHub OAuth, you'll login using your GitHub account (`Anie3142`), and you'll be automatically admin!

---

## 4️⃣ Create hello-django Repository

Create a new GitHub repo: `Anie3142/hello-django`

### Repository Structure:
```
hello-django/
├── Dockerfile
├── Jenkinsfile
├── requirements.txt
├── manage.py
├── config/
│   ├── __init__.py
│   ├── settings.py
│   ├── urls.py
│   └── wsgi.py
└── app/
    ├── __init__.py
    ├── views.py
    └── urls.py
```

### Sample Dockerfile:
```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "config.wsgi:application"]
```

### Sample Jenkinsfile:
```groovy
pipeline {
    agent any
    
    environment {
        AWS_REGION = 'us-east-1'
        ECR_REPO = '975049891041.dkr.ecr.us-east-1.amazonaws.com/nameless-hello-django'
        ECS_CLUSTER = 'nameless-cluster'
        ECS_SERVICE = 'nameless-hello-django'
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Build') {
            steps {
                script {
                    sh "docker build -t ${ECR_REPO}:${BUILD_NUMBER} ."
                    sh "docker tag ${ECR_REPO}:${BUILD_NUMBER} ${ECR_REPO}:latest"
                }
            }
        }
        
        stage('Push to ECR') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials']]) {
                    sh '''
                        aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REPO}
                        docker push ${ECR_REPO}:${BUILD_NUMBER}
                        docker push ${ECR_REPO}:latest
                    '''
                }
            }
        }
        
        stage('Deploy to ECS') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials']]) {
                    sh '''
                        # Get current task definition
                        TASK_DEF=$(aws ecs describe-task-definition --task-definition nameless-hello-django --region ${AWS_REGION})
                        
                        # Create new task definition with updated image
                        NEW_TASK_DEF=$(echo $TASK_DEF | jq --arg IMAGE "${ECR_REPO}:${BUILD_NUMBER}" '.taskDefinition | .containerDefinitions[0].image = $IMAGE | del(.taskDefinitionArn) | del(.revision) | del(.status) | del(.requiresAttributes) | del(.compatibilities) | del(.registeredAt) | del(.registeredBy)')
                        
                        # Register new task definition
                        NEW_TASK_DEF_ARN=$(aws ecs register-task-definition --region ${AWS_REGION} --cli-input-json "$NEW_TASK_DEF" --query 'taskDefinition.taskDefinitionArn' --output text)
                        
                        # Update service
                        aws ecs update-service --cluster ${ECS_CLUSTER} --service ${ECS_SERVICE} --task-definition $NEW_TASK_DEF_ARN --region ${AWS_REGION}
                    '''
                }
            }
        }
        
        stage('Verify Deployment') {
            steps {
                sh '''
                    # Wait for deployment
                    sleep 60
                    
                    # Health check
                    curl -f https://api.namelesscompany.cc/health/ || exit 1
                '''
            }
        }
    }
    
    post {
        success {
            echo '✅ Deployment successful!'
        }
        failure {
            echo '❌ Deployment failed!'
        }
    }
}
```

---

## 5️⃣ Configure GitHub Webhook

1. Go to GitHub repo → Settings → Webhooks → Add webhook

2. Configure:
   - **Payload URL**: `https://webhook.namelesscompany.cc/github-webhook/`
   - **Content type**: `application/json`
   - **Secret**: (get from SSM: `/nameless/github/webhook-secret`)
   - **Events**: Just the push event
   - **Active**: ✅ Yes

3. Test the webhook by clicking "Recent Deliveries" after making a push

---

## 6️⃣ Apply Terraform Changes

```bash
# Deploy hello-django infrastructure
cd infra/live/30-apps/hello-django
terraform init
terraform plan
terraform apply

# Update Cloudflare tunnel config
cd ../../../05-cloudflare
terraform plan
terraform apply
```

---

## 7️⃣ Test the Full CI/CD Flow

1. **Push to hello-django repo**:
   ```bash
   cd hello-django
   git add .
   git commit -m "Test CI/CD pipeline"
   git push origin main
   ```

2. **Watch Jenkins build**:
   - Go to https://jenkins.namelesscompany.cc
   - Navigate to hello-django job
   - Watch the pipeline run

3. **Verify deployment**:
   ```bash
   curl https://api.namelesscompany.cc/health/
   curl https://api.namelesscompany.cc/version/
   ```

---

## 🔧 Troubleshooting

### Webhook not triggering builds?
1. Check webhook delivery logs in GitHub
2. Verify webhook.namelesscompany.cc is NOT behind Cloudflare Access
3. Check Jenkins logs: `aws logs tail /ecs/nameless-jenkins --follow`

### Build fails with Docker permissions?
Jenkins needs Docker access. Either:
- Use Docker-in-Docker (DinD)
- Mount Docker socket from host
- Use EC2 build agent with Docker installed

### Service Discovery not resolving?
1. Check Cloud Map service exists: `aws servicediscovery list-services`
2. Verify ECS service is registered: `aws servicediscovery list-instances --service-id <id>`
3. Test from cloudflared: `curl http://hello-django.nameless.local:8000`

---

## 📊 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      GITHUB                                  │
│  ┌───────────────┐        ┌──────────────────────┐         │
│  │ hello-django  │─push──→│    GitHub Webhook    │         │
│  └───────────────┘        └──────────┬───────────┘         │
└──────────────────────────────────────┼─────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────┐
│                   CLOUDFLARE TUNNEL                         │
│  webhook.namelesscompany.cc → jenkins.nameless.local:8080   │
└──────────────────────────────────────┬─────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────┐
│                       AWS ECS                                │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────┐ │
│  │  Jenkins    │───→│     ECR      │───→│ hello-django   │ │
│  │  (Build)    │    │ (Push Image) │    │ (Deploy)       │ │
│  └─────────────┘    └──────────────┘    └───────┬────────┘ │
│                                                  │          │
│  Cloud Map: hello-django.nameless.local:8000 ◄──┘          │
└──────────────────────────────────────────────────┬─────────┘
                                                   │
                                                   ▼
┌─────────────────────────────────────────────────────────────┐
│                   CLOUDFLARE TUNNEL                         │
│  api.namelesscompany.cc → hello-django.nameless.local:8000  │
└─────────────────────────────────────────────────────────────┘
```

---

## ✅ Checklist

- [ ] Secrets stored in SSM
- [ ] Custom Jenkins image built and pushed to ECR
- [ ] Jenkins ECS service updated with new image
- [ ] hello-django repo created
- [ ] GitHub webhook configured
- [ ] hello-django Terraform stack applied
- [ ] Cloudflare tunnel config updated
- [ ] Full CI/CD flow tested
