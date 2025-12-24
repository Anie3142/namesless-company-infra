#!/bin/bash
# =============================================================================
# Destroy Infrastructure Script
# Destroys all infrastructure stacks in reverse order
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

# Function to destroy a stack
destroy_stack() {
    local stack_path="$1"
    local stack_name="$2"
    
    log_info "Destroying $stack_name..."
    cd "$INFRA_DIR/live/$stack_path"
    
    if [[ ! -d ".terraform" ]]; then
        log_warn "$stack_name not initialized, skipping..."
        return 0
    fi
    
    terraform init -upgrade
    terraform plan -destroy -out=tfplan-destroy
    
    echo ""
    read -p "Destroy $stack_name? (yes/no): " confirm
    if [[ "$confirm" == "yes" ]]; then
        terraform apply tfplan-destroy
        rm -f tfplan-destroy
        log_success "$stack_name destroyed!"
    else
        rm -f tfplan-destroy
        log_warn "Skipped $stack_name destruction"
        return 1
    fi
}

# Main destroy sequence
main() {
    echo ""
    echo "=============================================="
    echo "  Nameless Infrastructure DESTRUCTION"
    echo "=============================================="
    echo ""
    
    log_warn "WARNING: This will destroy ALL infrastructure!"
    log_warn "All data will be PERMANENTLY DELETED!"
    echo ""
    
    # Check AWS credentials
    log_info "Checking AWS credentials..."
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured."
        exit 1
    fi
    log_success "AWS credentials valid"
    echo ""
    
    # Show destruction order
    echo "Destruction order (reverse of deployment):"
    echo "  1. 30-apps/n8n - n8n Application"
    echo "  2. 20-ecs      - ECS Cluster, ALB, ECR, IAM"
    echo "  3. 10-network  - VPC, Subnets, NAT Instance"
    echo "  4. 00-state    - Terraform backend (OPTIONAL)"
    echo ""
    
    read -p "Type 'DESTROY' to confirm: " confirm
    if [[ "$confirm" != "DESTROY" ]]; then
        log_warn "Destruction cancelled"
        exit 0
    fi
    
    # Destroy in reverse order
    echo ""
    echo "=============================================="
    echo "  Step 1: Destroying n8n Application"
    echo "=============================================="
    destroy_stack "30-apps/n8n" "n8n Application" || true
    
    echo ""
    echo "=============================================="
    echo "  Step 2: Destroying ECS Platform"
    echo "=============================================="
    destroy_stack "20-ecs" "ECS Platform" || true
    
    echo ""
    echo "=============================================="
    echo "  Step 3: Destroying Network Infrastructure"
    echo "=============================================="
    destroy_stack "10-network" "Network Infrastructure" || true
    
    # Ask about state backend
    echo ""
    echo "=============================================="
    echo "  Step 4: Terraform State Backend (OPTIONAL)"
    echo "=============================================="
    log_warn "The state backend contains your Terraform state."
    log_warn "Only destroy this if you're completely removing the infrastructure."
    echo ""
    read -p "Destroy state backend? (yes/no): " state_confirm
    if [[ "$state_confirm" == "yes" ]]; then
        # Need to migrate to local state first
        cd "$INFRA_DIR/live/00-state"
        log_info "NOTE: You may need to comment out the S3 backend first"
        destroy_stack "00-state" "Terraform State Backend" || true
    else
        log_warn "State backend preserved"
    fi
    
    echo ""
    echo "=============================================="
    echo "  Destruction Complete"
    echo "=============================================="
    log_success "Infrastructure destroyed"
    echo ""
}

main "$@"
