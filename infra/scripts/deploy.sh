#!/bin/bash
# =============================================================================
# Deploy Infrastructure Script
# Deploys all infrastructure stacks in the correct order
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

# Function to print colored output
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to deploy a stack
deploy_stack() {
    local stack_path="$1"
    local stack_name="$2"
    
    log_info "Deploying $stack_name..."
    cd "$INFRA_DIR/live/$stack_path"
    
    terraform init -upgrade
    terraform plan -out=tfplan
    
    echo ""
    read -p "Apply $stack_name? (yes/no): " confirm
    if [[ "$confirm" == "yes" ]]; then
        terraform apply tfplan
        rm -f tfplan
        log_success "$stack_name deployed successfully!"
    else
        rm -f tfplan
        log_warn "Skipped $stack_name deployment"
        return 1
    fi
}

# Main deployment sequence
main() {
    echo ""
    echo "=============================================="
    echo "  Nameless Infrastructure Deployment"
    echo "=============================================="
    echo ""
    
    # Check AWS credentials
    log_info "Checking AWS credentials..."
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured. Please run 'aws sso login' or configure credentials."
        exit 1
    fi
    log_success "AWS credentials valid"
    echo ""
    
    # Show deployment order
    echo "Deployment order:"
    echo "  1. 00-state    - Terraform backend (S3 + DynamoDB)"
    echo "  2. 10-network  - VPC, Subnets, NAT Instance"
    echo "  3. 20-ecs      - ECS Cluster, ALB, ECR, IAM"
    echo "  4. 30-apps/n8n - n8n Application"
    echo ""
    
    read -p "Continue with deployment? (yes/no): " start_confirm
    if [[ "$start_confirm" != "yes" ]]; then
        log_warn "Deployment cancelled"
        exit 0
    fi
    
    # Deploy 00-state (uses local backend initially)
    echo ""
    echo "=============================================="
    echo "  Step 1: Terraform State Backend"
    echo "=============================================="
    deploy_stack "00-state" "Terraform State Backend" || exit 0
    
    echo ""
    log_warn "NOTE: After this first deployment, you should migrate the state"
    log_warn "to the S3 backend by uncommenting the backend block in 00-state/main.tf"
    log_warn "and running 'terraform init -migrate-state'"
    echo ""
    read -p "Press Enter to continue..."
    
    # Deploy 10-network
    echo ""
    echo "=============================================="
    echo "  Step 2: Network Infrastructure"
    echo "=============================================="
    deploy_stack "10-network" "Network Infrastructure" || exit 0
    
    # Deploy 20-ecs
    echo ""
    echo "=============================================="
    echo "  Step 3: ECS Platform"
    echo "=============================================="
    deploy_stack "20-ecs" "ECS Platform" || exit 0
    
    # Deploy 30-apps/n8n
    echo ""
    echo "=============================================="
    echo "  Step 4: n8n Application"
    echo "=============================================="
    deploy_stack "30-apps/n8n" "n8n Application" || exit 0
    
    # Show final outputs
    echo ""
    echo "=============================================="
    echo "  Deployment Complete!"
    echo "=============================================="
    echo ""
    
    # Get ALB DNS
    cd "$INFRA_DIR/live/20-ecs"
    ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "Unable to retrieve")
    
    echo ""
    log_success "Infrastructure deployed successfully!"
    echo ""
    echo "ALB DNS Name (for Cloudflare):"
    echo "  $ALB_DNS"
    echo ""
    echo "Next Steps:"
    echo "  1. Add a CNAME record in Cloudflare pointing to the ALB DNS"
    echo "  2. Set SSL mode to 'Full' in Cloudflare"
    echo "  3. Access n8n at https://your-domain.com"
    echo ""
}

main "$@"
