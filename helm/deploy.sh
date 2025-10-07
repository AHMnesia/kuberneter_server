#!/bin/bash

# Suma Platform Deployment Script
# Usage: ./deploy.sh [dev|production] [--skip-build] [--force-recreate]

set -e

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT=""
SKIP_BUILD    local namespaces=(
        "redis"
        "suma-android"
        "suma-ecommerce"
        "suma-office"
        "suma-pmo"
        "suma-chat"
        "suma-webhook"
        "elasticsearch"
        "kibana"
        "monitoring"
    )
    
    for ns in "${namespaces[@]}"; do
        echo -e "\033[1;33mNamespace: $ns\033[0m"ECREATE=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        dev|production)
            ENVIRONMENT=$arg
            ;;
        --skip-build)
            SKIP_BUILD=true
            ;;
        --force-recreate)
            FORCE_RECREATE=true
            ;;
        --help|-h)
            echo "Usage: $0 [dev|production] [options]"
            echo ""
            echo "Environments:"
            echo "  dev          Deploy development environment"
            echo "  production   Deploy production environment"
            echo ""
            echo "Options:"
            echo "  --skip-build      Skip Docker image building"
            echo "  --force-recreate  Force recreate all namespaces"
            echo "  --help, -h        Show this help message"
            exit 0
            ;;
    esac
done

# Validate environment
if [ -z "$ENVIRONMENT" ]; then
    echo -e "${RED}Error: Environment not specified${NC}"
    echo "Usage: $0 [dev|production] [options]"
    echo "Use --help for more information"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR=$(dirname "$SCRIPT_DIR")

# Set environment-specific values
if [ "$ENVIRONMENT" = "dev" ]; then
    VALUES_FILE="values-dev.yaml"
    IMAGE_TAG="latest"
    DOMAIN_SUFFIX="local"
else
    VALUES_FILE="values-production.yaml"
    IMAGE_TAG="production"
    DOMAIN_SUFFIX="suma-honda.id"
fi

# Functions for colored output
echo_status() {
    echo -e "${GREEN}[✔] $1${NC}"
}

echo_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

echo_error() {
    echo -e "${RED}[✘] $1${NC}"
    exit 1
}

echo_info() {
    echo -e "${CYAN}[i] $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    echo_info "Checking prerequisites..."
    
    if ! command -v kubectl &>/dev/null; then
        echo_error "kubectl is not installed"
    fi
    
    if ! command -v helm &>/dev/null; then
        echo_error "helm is not installed"
    fi
    
    if ! command -v docker &>/dev/null; then
        echo_error "docker is not installed"
    fi
    
    # Check if values file exists
    if [ ! -f "$SCRIPT_DIR/$VALUES_FILE" ]; then
        echo_error "Values file not found: $VALUES_FILE"
    fi
    
    echo_status "All prerequisites met"
}

# Build Docker images
build_images() {
    if [ "$SKIP_BUILD" = "true" ]; then
        echo_warning "Skipping Docker image build"
        return
    fi
    
    echo_status "Building Docker images with tag: $IMAGE_TAG"
    
    if [ -d "$PARENT_DIR/suma-android" ]; then
        echo_info "Building suma-android..."
        docker build -t suma-android-api:$IMAGE_TAG "$PARENT_DIR/suma-android"
    fi
    
    if [ -d "$PARENT_DIR/suma-ecommerce" ]; then
        echo_info "Building suma-ecommerce..."
        docker build -t suma-ecommerce-api:$IMAGE_TAG "$PARENT_DIR/suma-ecommerce"
    fi
    
    if [ -d "$PARENT_DIR/suma-office" ]; then
        echo_info "Building suma-office..."
        docker build -t suma-office-api:$IMAGE_TAG "$PARENT_DIR/suma-office"
    fi
    
    if [ -d "$PARENT_DIR/suma-pmo" ]; then
        echo_info "Building suma-pmo..."
        docker build -t suma-pmo-api:$IMAGE_TAG "$PARENT_DIR/suma-pmo"
    fi
    
    if [ -d "$PARENT_DIR/suma-chat" ]; then
        echo_info "Building suma-chat..."
        docker build -t suma-chat:$IMAGE_TAG "$PARENT_DIR/suma-chat"
    fi
    
    # Suma-webhook runs on host, not in K8s - skip building
    echo_info "Skipping suma-webhook (runs on host via systemd/task scheduler)"
    
    echo_status "Docker images built successfully"
}

# Setup cert-manager
setup_cert_manager() {
    echo_status "Checking cert-manager..."
    
    local cert_manager_yaml="$SCRIPT_DIR/vendor/cert-manager.yaml"
    
    if ! kubectl get namespace cert-manager &>/dev/null; then
        echo_info "Installing cert-manager from local file..."
        if [ -f "$cert_manager_yaml" ]; then
            kubectl apply -f "$cert_manager_yaml"
        else
            echo_warning "Local cert-manager.yaml not found, downloading from GitHub..."
            kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
        fi
        echo_info "Waiting for cert-manager to be ready..."
        kubectl wait --for=condition=ready pod --all -n cert-manager --timeout=180s
        sleep 10
        echo_status "cert-manager is ready"
    else
        echo_status "cert-manager already installed"
        # Verify cert-manager is actually running
        if ! kubectl get pods -n cert-manager &>/dev/null; then
            echo_warning "cert-manager namespace exists but no pods found. Reinstalling..."
            kubectl delete namespace cert-manager --ignore-not-found=true
            sleep 5
            if [ -f "$cert_manager_yaml" ]; then
                kubectl apply -f "$cert_manager_yaml"
            else
                kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
            fi
            echo_info "Waiting for cert-manager to be ready..."
            kubectl wait --for=condition=ready pod --all -n cert-manager --timeout=180s
            sleep 10
        fi
    fi
    
    # Create ClusterIssuer
    echo_info "Creating ClusterIssuer..."
    kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}
EOF
    
    echo_status "cert-manager setup complete"
}

# Setup metrics-server (optional but recommended)
setup_metrics_server() {
    echo_status "Checking metrics-server..."
    
    local metrics_server_yaml="$SCRIPT_DIR/vendor/metrics-server.yaml"
    
    if ! kubectl get deployment metrics-server -n kube-system &>/dev/null; then
        echo_info "Installing metrics-server from local file..."
        if [ -f "$metrics_server_yaml" ]; then
            kubectl apply -f "$metrics_server_yaml"
            echo_info "Waiting for metrics-server to be ready..."
            kubectl wait --for=condition=available deployment/metrics-server -n kube-system --timeout=120s 2>/dev/null || true
            echo_status "metrics-server is ready"
        else
            echo_warning "Local metrics-server.yaml not found. Skipping metrics-server installation."
            echo_warning "This is optional but recommended for resource monitoring."
        fi
    else
        echo_status "metrics-server already installed"
    fi
}

# Create namespaces
create_namespaces() {
    local namespaces=(
        "redis"
        "suma-android"
        "suma-ecommerce"
        "suma-office"
        "suma-pmo"
        "suma-chat"
        "suma-webhook"
        "elasticsearch"
        "kibana"
        "monitoring"
    )
    
    echo_status "Setting up namespaces..."
    
    for ns in "${namespaces[@]}"; do
        if [ "$FORCE_RECREATE" = "true" ]; then
            echo_info "Recreating namespace $ns..."
            kubectl delete namespace "$ns" --ignore-not-found=true &>/dev/null
            sleep 2
            kubectl create namespace "$ns"
        elif ! kubectl get namespace "$ns" &>/dev/null; then
            echo_info "Creating namespace $ns..."
            kubectl create namespace "$ns"
        else
            echo_status "Namespace $ns already exists"
        fi
    done
}

# Deploy Helm charts
deploy_charts() {
    echo_status "Deploying Helm charts for $ENVIRONMENT environment..."
    
    cd "$SCRIPT_DIR"
    
    # Update dependencies
    echo_info "Updating Helm dependencies..."
    helm dependency update .
    
    # Phase 1: Deploy infrastructure (Redis, Elasticsearch)
    local phase1_charts=(
        "redis-cluster:redis"
        "elasticsearch:elasticsearch"
    )
    
    echo_info "Phase 1: Deploying infrastructure (Redis, Elasticsearch)..."
    for chart_entry in "${phase1_charts[@]}"; do
        IFS=':' read -r chart_name namespace <<< "$chart_entry"
        chart_path="./charts/$chart_name"
        
        if [ ! -d "$chart_path" ]; then
            echo_warning "Chart not found: $chart_path"
            continue
        fi
        
        if helm list -n "$namespace" | grep -q "$chart_name"; then
            echo_info "Upgrading $chart_name in namespace $namespace..."
            helm upgrade "$chart_name" "$chart_path" \
                -n "$namespace" \
                -f "$VALUES_FILE" \
                --create-namespace \
                --timeout 5m
        else
            echo_info "Installing $chart_name in namespace $namespace..."
            helm install "$chart_name" "$chart_path" \
                -n "$namespace" \
                -f "$VALUES_FILE" \
                --create-namespace \
                --timeout 5m
        fi
    done
    
    # Wait for Elasticsearch to be ready before creating Kibana user
    echo_info "Waiting for Elasticsearch to be ready..."
    kubectl wait --for=condition=ready pod --all -n elasticsearch --timeout=300s 2>/dev/null || true
    sleep 10  # Extra wait for Elasticsearch to fully initialize
    
    # Phase 2: Create Kibana user (prerequisite for Kibana)
    echo_status "Creating Kibana user in Elasticsearch..."
    setup_kibana_user
    
    # Phase 3: Deploy Kibana and other services
    local phase2_charts=(
        "kibana:kibana"
        "suma-android:suma-android"
        "suma-ecommerce:suma-ecommerce"
        "suma-office:suma-office"
        "suma-pmo:suma-pmo"
        "suma-chat:suma-chat"
        "suma-webhook:suma-webhook"
        "monitoring:monitoring"
    )
    
    echo_info "Phase 2: Deploying applications (Kibana, Apps, Monitoring)..."
    echo_info "Note: suma-webhook chart only creates Service/Endpoints/Ingress (webhook runs on host)"
    
    for chart_entry in "${phase2_charts[@]}"; do
        IFS=':' read -r chart_name namespace <<< "$chart_entry"
        chart_path="./charts/$chart_name"
        
        if [ ! -d "$chart_path" ]; then
            echo_warning "Chart not found: $chart_path"
            continue
        fi
        
        if helm list -n "$namespace" | grep -q "$chart_name"; then
            echo_info "Upgrading $chart_name in namespace $namespace..."
            helm upgrade "$chart_name" "$chart_path" \
                -n "$namespace" \
                -f "$VALUES_FILE" \
                --create-namespace \
                --timeout 5m
        else
            echo_info "Installing $chart_name in namespace $namespace..."
            helm install "$chart_name" "$chart_path" \
                -n "$namespace" \
                -f "$VALUES_FILE" \
                --create-namespace \
                --timeout 5m
        fi
    done
    
    echo_status "All charts deployed successfully"
}

# Setup Kibana user in Elasticsearch
setup_kibana_user() {
    echo_status "Setting up Kibana user in Elasticsearch..."
    
    local kibana_script="$SCRIPT_DIR/perintah/create-kibana-user.sh"
    
    if [ -f "$kibana_script" ]; then
        echo_info "Running Kibana user creation script..."
        
        # Get Elasticsearch domain based on environment
        local es_domain
        if [ "$ENVIRONMENT" = "dev" ]; then
            es_domain="search.suma-honda.local"
        else
            es_domain="search.suma-honda.id"
        fi
        
        # Run the script with parameters
        if bash "$kibana_script" \
            --domain "$es_domain" \
            --user "elastic" \
            --pass "admin123" \
            --kibana-user "kibana_user" \
            --kibana-pass "kibanapass" \
            --max-wait 180; then
            echo_status "Kibana user created successfully"
        else
            echo_warning "Kibana user creation had issues (exit code: $?)"
            echo_info "Kibana may not connect to Elasticsearch properly"
        fi
    else
        echo_warning "Kibana user script not found: $kibana_script"
        echo_info "Kibana may not be able to connect to Elasticsearch"
    fi
}

# Setup webhook task scheduler on host
setup_webhook_scheduler() {
    echo_status "Setting up suma-webhook task scheduler on host..."
    
    local webhook_script="$SCRIPT_DIR/perintah/setup-webhook-scheduler.sh"
    
    if [ -f "$webhook_script" ]; then
        echo_info "Running webhook task scheduler setup..."
        
        # Check if running as root
        if [ "$EUID" -eq 0 ]; then
            bash "$webhook_script" install
            echo_status "Webhook task scheduler configured successfully"
        else
            echo_warning "Skipping webhook setup - requires root privileges"
            echo_info "Run this command manually with sudo:"
            echo "  sudo $webhook_script install"
        fi
    else
        echo_warning "Webhook scheduler script not found: $webhook_script"
    fi
}

# Wait for pods
wait_for_pods() {
    local namespaces=(
        "redis"
        "suma-android"
        "suma-ecommerce"
        "suma-office"
        "suma-pmo"
        "suma-chat"
        "suma-webhook"
        "elasticsearch"
        "kibana"
        "monitoring"
    )
    
    echo_status "Waiting for pods to be ready..."
    
    for ns in "${namespaces[@]}"; do
        echo_info "Checking pods in namespace $ns..."
        kubectl wait --for=condition=ready pod --all -n "$ns" --timeout=120s 2>/dev/null || true
    done
}

# Show deployment status
show_status() {
    echo ""
    echo "================================================================================"
    echo_status "Deployment Status for $ENVIRONMENT Environment"
    echo "================================================================================"
    echo ""
    
    local namespaces=(
        "redis"
        "suma-android"
        "suma-ecommerce"
        "suma-office"
        "suma-pmo"
        "suma-chat"
        "suma-webhook"
        "elasticsearch"
        "kibana"
        "monitoring"
    )
    
    for ns in "${namespaces[@]}"; do
        echo -e "${YELLOW}Namespace: $ns${NC}"
        echo -e "${CYAN}Pods:${NC}"
        kubectl get pods -n "$ns" 2>/dev/null || echo "  No pods found"
        echo ""
    done
}

# Show access URLs
show_urls() {
    echo ""
    echo "================================================================================"
    echo_status "Access URLs ($ENVIRONMENT Environment)"
    echo "================================================================================"
    echo ""
    
    if [ "$ENVIRONMENT" = "dev" ]; then
        echo -e "${CYAN}  Applications:${NC}"
        echo "    - Suma Android:    http://suma-android.local"
        echo "    - Suma E-commerce: http://suma-ecommerce.local"
        echo "    - Suma Office:     http://suma-office.local"
        echo "    - Suma PMO:        http://suma-pmo.local"
        echo "    - Suma Chat:       http://suma-chat.local"
        echo ""
        echo -e "${CYAN}  Infrastructure:${NC}"
        echo "    - Elasticsearch:   http://search.suma-honda.local"
        echo "    - Kibana:          http://kibana.suma-honda.local"
        echo "    - Monitoring:      http://monitoring.suma-honda.local"
        echo ""
        echo -e "${CYAN}  API Gateway:${NC}"
        echo "    - API Base:        http://api.suma-honda.id"
        echo "    - Android API:     http://api.suma-honda.id/android"
        echo "    - E-commerce API:  http://api.suma-honda.id/ecommerce"
        echo "    - Office API:      http://api.suma-honda.id/office"
        echo "    - PMO API:         http://api.suma-honda.id/pmo"
        echo "    - Chat API:        http://api.suma-honda.id/chat"
        echo ""
        echo_warning "Note: Add these entries to /etc/hosts (or C:\\Windows\\System32\\drivers\\etc\\hosts):"
        echo "  127.0.0.1 suma-android.local suma-ecommerce.local suma-office.local"
        echo "  127.0.0.1 suma-pmo.local suma-chat.local"
        echo "  127.0.0.1 search.suma-honda.local kibana.suma-honda.local monitoring.suma-honda.local"
        echo "  127.0.0.1 api.suma-honda.id webhook.suma-honda.local"
    else
        echo -e "${CYAN}  Applications:${NC}"
        echo "    - Suma Android:    https://suma-android.suma-honda.id"
        echo "    - Suma E-commerce: https://suma-ecommerce.suma-honda.id"
        echo "    - Suma Office:     https://suma-office.suma-honda.id"
        echo "    - Suma PMO:        https://suma-pmo.suma-honda.id"
        echo "    - Suma Chat:       https://suma-chat.suma-honda.id"
        echo ""
        echo -e "${CYAN}  Infrastructure:${NC}"
        echo "    - Elasticsearch:   https://search.suma-honda.id"
        echo "    - Kibana:          https://kibana.suma-honda.id"
        echo "    - Monitoring:      https://monitoring.suma-honda.id"
        echo ""
        echo -e "${CYAN}  API Gateway:${NC}"
        echo "    - API Base:        https://api.suma-honda.id"
        echo "    - Android API:     https://api.suma-honda.id/android"
        echo "    - E-commerce API:  https://api.suma-honda.id/ecommerce"
        echo "    - Office API:      https://api.suma-honda.id/office"
        echo "    - PMO API:         https://api.suma-honda.id/pmo"
        echo "    - Chat API:        https://api.suma-honda.id/chat"
    fi
    echo ""
}

# Main execution
main() {
    echo ""
    echo "================================================================================"
    echo_status "Suma Platform Deployment Script"
    echo_info "Environment: $ENVIRONMENT"
    echo_info "Values File: $VALUES_FILE"
    echo_info "Image Tag:   $IMAGE_TAG"
    echo "================================================================================"
    echo ""
    
    check_prerequisites
    build_images
    setup_cert_manager
    setup_metrics_server
    create_namespaces
    setup_webhook_scheduler
    deploy_charts
    wait_for_pods
    show_status
    show_urls
    
    echo ""
    echo "================================================================================"
    echo_status "Deployment Complete!"
    echo "================================================================================"
    echo ""
}

# Run main function
main
