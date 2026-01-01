# 🔄 AI Handover Document - Personal Finance App (NairaTrack)

## 📋 Project Overview

**NairaTrack** is a personal finance management application with:
- **Frontend**: Next.js 14 app deployed to Cloudflare Workers
- **Backend**: Django REST API deployed to AWS ECS
- **Database**: PostgreSQL on AWS RDS
- **Authentication**: Auth0 (OAuth 2.0 / OIDC)
- **CI/CD**: Jenkins on ECS, auto-deploys on git push

---

## 📁 Repository Locations

| Repository | Path | Description |
|------------|------|-------------|
| **Frontend** | `/Users/aniebiet-abasiudo/code-repo/personal-finance-fe` | Next.js + Cloudflare Workers |
| **Backend** | `/Users/aniebiet-abasiudo/code-repo/personal-finance-be` | Django REST API |
| **Infrastructure** | `/Users/aniebiet-abasiudo/code-repo/namesless-company-infra` | Terraform IaC |

---

## 🌐 Live URLs

| Service | URL | Description |
|---------|-----|-------------|
| Frontend | https://personal-finance.namelesscompany.cc | Next.js on Cloudflare Workers |
| Backend API | https://personal-finance-api.namelesscompany.cc | Django on AWS ECS |
| Jenkins CI/CD | https://jenkins.namelesscompany.cc | CI/CD dashboard |
| n8n Automation | https://n8n.namelesscompany.cc | Workflow automation |

---

## 🔧 AWS CLI Access

You have access to AWS CLI. Use it to interact with AWS resources:

```bash
# Check AWS identity
aws sts get-caller-identity

# List ECS services
aws ecs list-services --cluster nameless-cluster

# View running tasks
aws ecs list-tasks --cluster nameless-cluster --service-name personal-finance-api
```

### 🗄️ Database Access via SSM Session Manager

The RDS database is in a private subnet. To connect:

```bash
# 1. Start SSM session to bastion/jump instance
aws ssm start-session --target <EC2_INSTANCE_ID>

# 2. From inside the EC2 instance, connect to RDS:
psql -h personal-finance-db.xxxxx.us-east-1.rds.amazonaws.com -U nairatrack -d personal_finance

# Get the RDS hostname from SSM Parameter:
aws ssm get-parameter --name "/nameless/personal-finance/db-endpoint" --query 'Parameter.Value' --output text
```

**Database Credentials** (stored in SSM Parameter Store):
- Endpoint: `/nameless/personal-finance/db-endpoint`
- Username: `nairatrack`
- Password: `/nameless/personal-finance/db-password` (SecureString)

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           CLOUDFLARE                                 │
│  ┌─────────────────────┐       ┌──────────────────────────────────┐ │
│  │   Workers (FE)      │       │      Tunnel → Traefik → ECS     │ │
│  │   Next.js App       │       │      (Backend API routing)       │ │
│  └─────────────────────┘       └──────────────────────────────────┘ │
│         ↓                                    ↓                       │
│  personal-finance.                personal-finance-api.             │
│  namelesscompany.cc               namelesscompany.cc                │
└─────────────────────────────────────────────────────────────────────┘
                                           │
                                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                              AWS                                     │
│  ┌─────────────────┐    ┌──────────────┐    ┌────────────────────┐ │
│  │   ECS Cluster   │    │   RDS        │    │  ECR               │ │
│  │  - API Service  │◄───│  PostgreSQL  │    │  Docker Images     │ │
│  │  - Jenkins      │    │  (private)   │    │  - personal-finance│ │
│  │  - Traefik      │    └──────────────┘    │  - jenkins         │ │
│  │  - Cloudflared  │                        └────────────────────┘ │
│  └─────────────────┘                                                │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🔐 Authentication Flow

### Frontend (Next.js)
- Uses `@auth0/nextjs-auth0` SDK
- Auth routes: `/api/auth/[auth0]/route.ts` (handles login, callback, logout)
- After login, frontend gets an ID token and access token from Auth0

### Backend (Django)
- Uses custom `Auth0JWTAuthentication` class
- Validates JWT tokens from Auth0
- Creates/updates user in Django on first login
- All API endpoints require authentication (except health check)

### Auth0 Configuration
```
Domain: dev-54nxe440ro81hlb6.us.auth0.com
Client ID: SM3sFfXc1ntYVIeWY1g16pVnuSsYUI7k
API Audience: https://api.personal-finance.namelesscompany.cc
```

---

## 🔌 What's Connected vs. Not Connected

### ✅ Already Working
1. **Infrastructure**: ECS, RDS, Cloudflare Tunnel, DNS - all deployed and running
2. **CI/CD**: Jenkins builds and deploys both FE and BE on git push
3. **Frontend**: Next.js app deployed to Workers with Auth0 login page
4. **Backend**: Django API running on ECS, connected to RDS
5. **Auth0**: Configured in both FE and BE

### ⚠️ Needs Work
1. **Frontend Auth → Backend API Connection**
   - Frontend needs to send Auth0 access token to backend API
   - Backend needs Auth0 API configured to issue access tokens (not just ID tokens)
   - Frontend needs API client to make authenticated requests

2. **Auth0 API Setup**
   - Need to create an Auth0 API in the Auth0 dashboard
   - API identifier should be: `https://api.personal-finance.namelesscompany.cc`
   - Configure frontend to request audience in token

3. **Frontend API Calls**
   - Need to create API client/hooks to call backend
   - Need to attach Bearer token to requests
   - Need to handle token refresh

---

## 📡 Backend API Endpoints

Base URL: `https://personal-finance-api.namelesscompany.cc/api/v1`

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check (public) |
| `/auth/me` | GET | Current user profile |
| `/accounts` | GET, POST | Bank accounts |
| `/accounts/{id}` | GET, PUT, DELETE | Single account |
| `/transactions` | GET, POST | Transactions list |
| `/transactions/{id}` | GET, PUT, DELETE | Single transaction |
| `/categories` | GET, POST | Categories |
| `/budgets` | GET, POST | Budgets |
| `/goals` | GET, POST | Savings goals |
| `/recurring` | GET, POST | Recurring transactions |
| `/reports/monthly` | GET | Monthly report |
| `/reports/net-worth` | GET | Net worth report |
| `/insights` | GET | AI-generated insights |

---

## 🐳 Local Development with Docker Compose

### Start All Services (from personal-finance-be folder)
```bash
cd /Users/aniebiet-abasiudo/code-repo/personal-finance-be
docker-compose up
```

This starts:
- **PostgreSQL** on `localhost:5432`
- **Django API** on `localhost:8000`
- **Next.js Frontend** on `localhost:3000`

### Local Environment Variables
**Frontend** (`.env.local` in personal-finance-fe):
```env
AUTH0_SECRET=2791dad30562134a65fb474e33da3ae56c3f149d140b4570ef1d491f9fa058e6
AUTH0_BASE_URL=http://localhost:3000
AUTH0_ISSUER_BASE_URL=https://dev-54nxe440ro81hlb6.us.auth0.com
AUTH0_CLIENT_ID=SM3sFfXc1ntYVIeWY1g16pVnuSsYUI7k
AUTH0_CLIENT_SECRET=<see .env.local file>
NEXT_PUBLIC_API_BASE_URL=http://localhost:8000/api/v1
```

**Backend** (docker-compose.yml sets these):
```env
DJANGO_SETTINGS_MODULE=config.settings.dev
DB_HOST=db
DB_NAME=nairatrack
AUTH0_DOMAIN=dev-54nxe440ro81hlb6.us.auth0.com
AUTH0_API_AUDIENCE=https://api.personal-finance.namelesscompany.cc
```

---

## 🚀 Deployment Process

### Frontend (Cloudflare Workers)
1. Push to `main` branch
2. GitHub webhook triggers Jenkins
3. Jenkins runs `npm run build:cloudflare`
4. Jenkins runs `wrangler deploy`
5. Live at https://personal-finance.namelesscompany.cc

### Backend (AWS ECS)
1. Push to `main` branch
2. GitHub webhook triggers Jenkins
3. Jenkins builds Docker image
4. Jenkins pushes to ECR
5. Jenkins updates ECS service
6. Live at https://personal-finance-api.namelesscompany.cc

---

## 📝 Key Files to Know

### Frontend (`personal-finance-fe`)
| File | Purpose |
|------|---------|
| `src/app/api/auth/[auth0]/route.ts` | Auth0 authentication handler |
| `src/app/(dashboard)/` | Protected dashboard routes |
| `wrangler.toml` | Cloudflare Workers config |
| `Jenkinsfile` | CI/CD pipeline |
| `.env.local` | Environment variables |

### Backend (`personal-finance-be`)
| File | Purpose |
|------|---------|
| `backend/apps/core/authentication.py` | Auth0 JWT validation |
| `backend/apps/core/urls.py` | All API routes |
| `backend/apps/core/views.py` | API view implementations |
| `backend/config/settings/prod.py` | Production settings |
| `docker-compose.yml` | Local dev environment |
| `Jenkinsfile` | CI/CD pipeline |
| `terraform/main.tf` | ECS service deployment |

### Infrastructure (`namesless-company-infra`)
| File | Purpose |
|------|---------|
| `infra/live/05-cloudflare/main.tf` | DNS, Tunnel, cloudflared |
| `infra/live/10-network/main.tf` | VPC, subnets |
| `infra/live/15-database/main.tf` | RDS PostgreSQL |
| `infra/live/20-ecs/main.tf` | ECS cluster |
| `infra/live/25-cicd/jenkins/main.tf` | Jenkins service |
| `infra/live/27-traefik/main.tf` | Traefik reverse proxy |

---

## 🔧 Tasks for the Next AI

### Priority 1: Connect Frontend to Backend
1. **Create Auth0 API** in Auth0 Dashboard:
   - Identifier: `https://api.personal-finance.namelesscompany.cc`
   - Enable "Allow Offline Access" for refresh tokens

2. **Update Frontend** to request access token with audience:
   ```typescript
   // In auth config, add audience
   AUTH0_AUDIENCE=https://api.personal-finance.namelesscompany.cc
   ```

3. **Create API client** in frontend to make authenticated requests:
   ```typescript
   // Example: fetcher with auth token
   const response = await fetch(`${process.env.NEXT_PUBLIC_API_BASE_URL}/accounts`, {
     headers: {
       Authorization: `Bearer ${accessToken}`
     }
   });
   ```

4. **Test the flow**:
   - Login on frontend
   - Call `/api/v1/auth/me` to verify backend auth works
   - Call other endpoints

### Priority 2: Implement Dashboard Features
- Dashboard should display accounts, transactions, budgets
- Create React Query hooks for API calls
- Implement data fetching and state management

### Priority 3: Local Development Improvements
- Ensure `docker-compose up` works seamlessly
- Add seed data script for development
- Add database migration checks

---

## ⚠️ Important Notes

1. **Auth0 API Token**: The backend expects an access token with:
   - `iss`: `https://dev-54nxe440ro81hlb6.us.auth0.com/`
   - `aud`: `https://api.personal-finance.namelesscompany.cc`

2. **Dev vs Prod Authentication**:
   - In development (`config.settings.dev`), uses `DevAuthentication` which auto-logs in as test user
   - In production (`config.settings.prod`), uses `Auth0JWTAuthentication` which validates real tokens

3. **Database Access**:
   - Production RDS is in private subnet
   - Must use SSM Session Manager to connect
   - No public IP or direct access

4. **Secrets Management**:
   - All secrets stored in AWS SSM Parameter Store
   - Retrieved by ECS task at runtime
   - Never committed to git

---

## 🔗 Quick Reference Commands

```bash
# Test backend API health
curl https://personal-finance-api.namelesscompany.cc/api/v1/health

# Test frontend
curl https://personal-finance.namelesscompany.cc

# View ECS service logs
aws logs tail /ecs/personal-finance-api --follow

# Force ECS deployment
aws ecs update-service --cluster nameless-cluster --service personal-finance-api --force-new-deployment

# Connect to RDS (via SSM session)
aws ssm start-session --target i-xxxxx
# Then: psql -h <rds-endpoint> -U nairatrack -d personal_finance
```

---

*Last Updated: January 1, 2026*
*Prepared by: Infrastructure AI*
