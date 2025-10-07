#!/bin/bash
# Create Kibana User in Elasticsearch
# Usage: ./create-kibana-user.sh [options]

# Default values
ELASTICSEARCH_DOMAIN="search.suma-honda.local"
ELASTICSEARCH_USER="elastic"
ELASTICSEARCH_PASS="admin123"
KIBANA_USER_NAME="kibana_user"
KIBANA_USER_PASS="kibanapass"
MAX_WAIT_SECONDS=300
CHECK_INTERVAL=5

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
DARK_GRAY='\033[1;30m'
NC='\033[0m' # No Color

# Functions
print_error() {
    echo -e "${RED}[x]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================${NC}"
    echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain|-d)
            ELASTICSEARCH_DOMAIN="$2"
            shift 2
            ;;
        --user|-u)
            ELASTICSEARCH_USER="$2"
            shift 2
            ;;
        --pass|-p)
            ELASTICSEARCH_PASS="$2"
            shift 2
            ;;
        --kibana-user)
            KIBANA_USER_NAME="$2"
            shift 2
            ;;
        --kibana-pass)
            KIBANA_USER_PASS="$2"
            shift 2
            ;;
        --max-wait)
            MAX_WAIT_SECONDS="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --domain, -d <domain>      Elasticsearch domain (default: search.suma-honda.local)"
            echo "  --user, -u <user>          Elasticsearch admin user (default: elastic)"
            echo "  --pass, -p <password>      Elasticsearch admin password (default: admin123)"
            echo "  --kibana-user <user>       Kibana user name (default: kibana_user)"
            echo "  --kibana-pass <password>   Kibana user password (default: kibanapass)"
            echo "  --max-wait <seconds>       Max wait time for ES (default: 300)"
            echo "  --help, -h                 Show this help"
            echo ""
            echo "Example:"
            echo "  $0 --domain search.suma-honda.id --kibana-pass strongpass123"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

print_header "Create Kibana User in Elasticsearch"

print_info "Configuration:"
echo -e "  ${GRAY}Elasticsearch Domain: $ELASTICSEARCH_DOMAIN${NC}"
echo -e "  ${GRAY}Elasticsearch User:   $ELASTICSEARCH_USER${NC}"
echo -e "  ${GRAY}Kibana User:          $KIBANA_USER_NAME${NC}"
echo -e "  ${GRAY}Max Wait:             $MAX_WAIT_SECONDS seconds${NC}"
echo ""

# Check curl exists
check_curl() {
    if ! command -v curl &> /dev/null; then
        print_error "curl not found"
        print_info "Install curl first:"
        echo "  Ubuntu/Debian: sudo apt-get install curl"
        echo "  CentOS/RHEL:   sudo yum install curl"
        echo "  macOS:         brew install curl"
        exit 1
    fi
    print_success "curl found: $(which curl)"
}

# Wait for Elasticsearch to be ready
wait_for_elasticsearch() {
    local domain=$1
    local user=$2
    local pass=$3
    local max_wait=$4
    local interval=$5
    
    local elapsed=0
    print_info "Waiting for Elasticsearch to be ready..."
    
    while [ $elapsed -lt $max_wait ]; do
        local remaining=$((max_wait - elapsed))
        echo -e "  ${DARK_GRAY}Checking https://${domain}/ ... (remaining: ${remaining} seconds)${NC}"
        
        local status=$(curl -k -u "${user}:${pass}" -s -o /dev/null -w "%{http_code}" "https://${domain}/" 2>/dev/null)
        
        if [ "$status" = "200" ]; then
            print_success "Elasticsearch is accessible at https://${domain}/"
            return 0
        else
            echo -e "  ${YELLOW}Status: $status (not ready yet)${NC}"
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    print_error "Timeout: Elasticsearch not accessible after $max_wait seconds"
    return 1
}

# Create Kibana user
create_kibana_user() {
    local domain=$1
    local user=$2
    local pass=$3
    local kibana_user=$4
    local kibana_pass=$5
    
    print_info "Creating Kibana user '$kibana_user' in Elasticsearch..."
    
    # Prepare request body
    local body=$(cat <<EOF
{
  "password": "$kibana_pass",
  "roles": ["kibana_system"]
}
EOF
)
    
    local url="https://${domain}/_security/user/${kibana_user}"
    
    echo -e "  ${DARK_GRAY}Request URL: $url${NC}"
    echo -e "  ${DARK_GRAY}Request Body: $body${NC}"
    
    # Execute curl command
    local result=$(curl -k -u "${user}:${pass}" \
        -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$body" \
        2>&1)
    
    echo -e "  ${GRAY}Response: $result${NC}"
    
    # Check result
    if echo "$result" | grep -q '"created"\s*:\s*true'; then
        print_success "Kibana user '$kibana_user' created successfully"
        return 0
    elif echo "$result" | grep -q '"created"\s*:\s*false\|already exists'; then
        print_warning "Kibana user '$kibana_user' already exists"
        return 0
    elif echo "$result" | grep -q '"updated"\s*:\s*true'; then
        print_success "Kibana user '$kibana_user' updated successfully"
        return 0
    else
        print_error "Failed to create Kibana user"
        print_info "Response details: $result"
        return 1
    fi
}

# Verify user was created
verify_kibana_user() {
    local domain=$1
    local user=$2
    local pass=$3
    local kibana_user=$4
    
    print_info "Verifying Kibana user '$kibana_user'..."
    
    local url="https://${domain}/_security/user/${kibana_user}"
    local result=$(curl -k -u "${user}:${pass}" -s "$url" 2>&1)
    
    if echo "$result" | grep -q "kibana_system\|$kibana_user"; then
        print_success "Kibana user verified successfully"
        echo -e "  ${GRAY}User info: $result${NC}"
        return 0
    else
        print_warning "Could not verify Kibana user"
        return 1
    fi
}

# Main execution
main() {
    # Check prerequisites
    check_curl
    
    # Wait for Elasticsearch
    echo ""
    if ! wait_for_elasticsearch "$ELASTICSEARCH_DOMAIN" "$ELASTICSEARCH_USER" "$ELASTICSEARCH_PASS" "$MAX_WAIT_SECONDS" "$CHECK_INTERVAL"; then
        print_error "Elasticsearch is not accessible"
        print_info "Check:"
        echo "  1. Elasticsearch pod is running: kubectl get pods -n elasticsearch"
        echo "  2. Service is accessible: kubectl get svc -n elasticsearch"
        echo "  3. Ingress is configured: kubectl get ingress -n elasticsearch"
        echo "  4. Domain is resolvable: nslookup $ELASTICSEARCH_DOMAIN"
        echo "  5. Hosts file configured: /etc/hosts"
        exit 1
    fi
    
    # Create Kibana user
    echo ""
    if ! create_kibana_user "$ELASTICSEARCH_DOMAIN" "$ELASTICSEARCH_USER" "$ELASTICSEARCH_PASS" "$KIBANA_USER_NAME" "$KIBANA_USER_PASS"; then
        print_error "Failed to create Kibana user"
        exit 1
    fi
    
    # Verify user
    echo ""
    verify_kibana_user "$ELASTICSEARCH_DOMAIN" "$ELASTICSEARCH_USER" "$ELASTICSEARCH_PASS" "$KIBANA_USER_NAME"
    
    # Success
    echo ""
    echo -e "${GREEN}================================${NC}"
    print_success "Kibana User Setup Complete!"
    echo -e "${GREEN}================================${NC}"
    echo ""
    echo -e "${CYAN}Kibana Configuration:${NC}"
    echo -e "  ${WHITE}Username: $KIBANA_USER_NAME${NC}"
    echo -e "  ${WHITE}Password: $KIBANA_USER_PASS${NC}"
    echo -e "  ${WHITE}Role:     kibana_system${NC}"
    echo ""
    print_info "Update Kibana configuration with these credentials"
    echo -e "  ${GRAY}kubectl edit configmap kibana-config -n kibana${NC}"
    echo -e "  ${GRAY}or update values.yaml and redeploy${NC}"
    echo ""
}

# Run main function
main
