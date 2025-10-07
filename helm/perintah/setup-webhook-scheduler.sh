#!/bin/bash
# Suma Webhook Task Scheduler Setup Script (Linux/Mac)
# Usage: sudo ./setup-webhook-scheduler.sh [install|uninstall|status]
# Note: Must run with sudo

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Functions
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================${NC}"
    echo ""
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Get actual user (not root if using sudo)
ACTUAL_USER="${SUDO_USER:-$USER}"
if [[ "$ACTUAL_USER" == "root" ]]; then
    ACTUAL_USER_HOME="/root"
else
    ACTUAL_USER_HOME="/home/$ACTUAL_USER"
fi

# Paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HELM_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$HELM_DIR")"
WEBHOOK_DIR="$ROOT_DIR/suma-webhook"
WEBHOOK_JS="$WEBHOOK_DIR/webhook.js"

ACTION="${1:-install}"

print_header "Suma Webhook Task Scheduler Setup"

# Check webhook.js exists
if [[ ! -f "$WEBHOOK_JS" ]]; then
    print_error "webhook.js not found at: $WEBHOOK_JS"
    exit 1
fi

print_info "Webhook file found: $WEBHOOK_JS"

# Check Node.js
if ! command -v node &> /dev/null; then
    print_error "Node.js is not installed"
    print_warning "Install Node.js first:"
    echo "  Ubuntu/Debian: curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash - && sudo apt-get install -y nodejs"
    echo "  CentOS/RHEL:   curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash - && sudo yum install -y nodejs"
    echo "  macOS:         brew install node"
    exit 1
fi

NODE_VERSION=$(node -v)
print_info "Node.js version: $NODE_VERSION"

# Check npm and install dependencies
print_info "Checking webhook dependencies..."
cd "$WEBHOOK_DIR"

if [[ -f "package.json" ]]; then
    if [[ ! -d "node_modules" ]] || [[ ! -f "package-lock.json" ]]; then
        print_info "Installing npm dependencies..."
        npm install --production
        print_success "Dependencies installed successfully"
    else
        print_success "Dependencies already installed"
    fi
fi

# Service configuration
SERVICE_NAME="suma-webhook"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

# Status check
if [[ "$ACTION" == "status" ]]; then
    echo ""
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "Service is running"
        systemctl status "$SERVICE_NAME" --no-pager
    else
        print_warning "Service is not running"
        if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
            print_info "Service is enabled but not running"
        else
            print_info "Service is not installed or not enabled"
        fi
    fi
    
    # Check port 5000
    echo ""
    if netstat -tlnp 2>/dev/null | grep -q ":5000 "; then
        print_info "Port 5000 is in use:"
        netstat -tlnp | grep ":5000 "
    else
        print_warning "Port 5000 is not in use"
    fi
    exit 0
fi

# Uninstall
if [[ "$ACTION" == "uninstall" ]]; then
    echo ""
    print_info "Uninstalling webhook service..."
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_info "Stopping service..."
        systemctl stop "$SERVICE_NAME"
        print_success "Service stopped"
    fi
    
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        print_info "Disabling service..."
        systemctl disable "$SERVICE_NAME"
        print_success "Service disabled"
    fi
    
    if [[ -f "$SERVICE_FILE" ]]; then
        print_info "Removing service file..."
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        print_success "Service file removed"
    fi
    
    # Kill any remaining webhook process on port 5000
    if netstat -tlnp 2>/dev/null | grep -q ":5000 "; then
        print_info "Stopping webhook process on port 5000..."
        PID=$(netstat -tlnp 2>/dev/null | grep ":5000 " | awk '{print $7}' | cut -d'/' -f1)
        if [[ ! -z "$PID" ]]; then
            kill -9 $PID 2>/dev/null || true
            print_success "Webhook process stopped"
        fi
    fi
    
    print_header "Uninstall Complete!"
    exit 0
fi

# Install/Update service
echo ""
print_info "Setting up webhook service..."

# Stop if running
if systemctl is-active --quiet "$SERVICE_NAME"; then
    print_info "Stopping existing service..."
    systemctl stop "$SERVICE_NAME"
    sleep 2
    print_info "Service stopped"
fi

# Create systemd service file
print_info "Creating systemd service file..."

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Suma Webhook Service
Documentation=https://github.com/suma/webhook
After=network.target

[Service]
Type=simple
User=$ACTUAL_USER
WorkingDirectory=$WEBHOOK_DIR
ExecStart=$(which node) $WEBHOOK_JS
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=suma-webhook

# Resource limits
LimitNOFILE=65536
MemoryLimit=512M

# Environment
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

print_success "Service file created: $SERVICE_FILE"

# Fix permissions
chown root:root "$SERVICE_FILE"
chmod 644 "$SERVICE_FILE"

# Reload systemd
print_info "Reloading systemd daemon..."
systemctl daemon-reload

# Enable service
print_info "Enabling service to start on boot..."
systemctl enable "$SERVICE_NAME"
print_success "Service enabled"

# Start service
print_info "Starting webhook service..."
systemctl start "$SERVICE_NAME"

# Wait and check status
sleep 3

if systemctl is-active --quiet "$SERVICE_NAME"; then
    print_success "Webhook service is running"
    
    # Check port 5000
    if netstat -tlnp 2>/dev/null | grep -q ":5000 "; then
        print_success "Webhook is listening on port 5000"
    else
        print_warning "Webhook may not be listening on port 5000 yet"
    fi
else
    print_error "Failed to start webhook service"
    print_info "Check logs with: journalctl -u $SERVICE_NAME -f"
    exit 1
fi

print_header "Setup Complete!"

echo -e "${WHITE}Service Name:${NC} $SERVICE_NAME"
echo -e "${WHITE}Webhook will start automatically on system boot${NC}"
echo ""
echo -e "${CYAN}Commands:${NC}"
echo -e "  ${GRAY}View status:    sudo systemctl status $SERVICE_NAME${NC}"
echo -e "  ${GRAY}Start service:  sudo systemctl start $SERVICE_NAME${NC}"
echo -e "  ${GRAY}Stop service:   sudo systemctl stop $SERVICE_NAME${NC}"
echo -e "  ${GRAY}Restart:        sudo systemctl restart $SERVICE_NAME${NC}"
echo -e "  ${GRAY}View logs:      sudo journalctl -u $SERVICE_NAME -f${NC}"
echo -e "  ${GRAY}Check webhook:  sudo netstat -tlnp | grep :5000${NC}"
echo -e "  ${GRAY}Uninstall:      sudo ./setup-webhook-scheduler.sh uninstall${NC}"
echo ""
