#!/bin/bash

set -euo pipefail

# Script metadata
SCRIPT_NAME="deploy.sh"
VERSION="1.0.0"
AUTHOR="DevOps Intern"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"

# Global variables
GIT_REPO=""
PAT=""
BRANCH="main"
SSH_USER=""
SERVER_IP=""
SSH_KEY_PATH=""
APP_PORT=""
CLONE_DIR=""
PROJECT_NAME=""

# Function to log messages
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${level}: ${message}"
    echo "[${timestamp}] ${level}: ${message}" >> "$LOG_FILE"
}

log_info() {
    log "${BLUE}INFO${NC}" "$1"
}

log_success() {
    log "${GREEN}SUCCESS${NC}" "$1"
}

log_warning() {
    log "${YELLOW}WARNING${NC}" "$1"
}

log_error() {
    log "${RED}ERROR${NC}" "$1"
}

# Trap for error handling
cleanup() {
    log_warning "Script interrupted. Performing cleanup..."
    # Add any cleanup operations here
    exit 1
}

trap cleanup SIGINT SIGTERM

# Function to validate input
validate_input() {
    if [[ -z "$GIT_REPO" ]]; then
        log_error "Git repository URL is required"
        exit 1
    fi
    
    if [[ -z "$PAT" ]]; then
        log_error "Personal Access Token is required"
        exit 1
    fi
    
    if [[ -z "$SSH_USER" ]]; then
        log_error "SSH username is required"
        exit 1
    fi
    
    if [[ -z "$SERVER_IP" ]]; then
        log_error "Server IP address is required"
        exit 1
    fi
    
    if [[ -z "$SSH_KEY_PATH" ]]; then
        log_error "SSH key path is required"
        exit 1
    fi
    
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        log_error "SSH key file not found: $SSH_KEY_PATH"
        exit 1
    fi
    
    if [[ -z "$APP_PORT" ]]; then
        log_error "Application port is required"
        exit 1
    fi
    
    if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]] || [ "$APP_PORT" -lt 1 ] || [ "$APP_PORT" -gt 65535 ]; then
        log_error "Invalid application port: $APP_PORT"
        exit 1
    fi
}

# Function to get user input
get_user_input() {
    echo -e "${BLUE}=== Automated Deployment Script ===${NC}"
    echo
    
    read -p "Git Repository URL: " GIT_REPO
    read -s -p "Personal Access Token: " PAT
    echo
    read -p "Branch name [main]: " BRANCH
    BRANCH=${BRANCH:-main}
    read -p "SSH Username: " SSH_USER
    read -p "Server IP Address: " SERVER_IP
    read -p "SSH Key Path: " SSH_KEY_PATH
    read -p "Application Port: " APP_PORT
    
    # Extract project name from repo URL
    PROJECT_NAME=$(basename -s .git "$GIT_REPO")
    CLONE_DIR="$PROJECT_NAME"
    
    log_info "Configuration:"
    log_info "Repository: $GIT_REPO"
    log_info "Branch: $BRANCH"
    log_info "Server: $SSH_USER@$SERVER_IP"
    log_info "Project: $PROJECT_NAME"
    log_info "Port: $APP_PORT"
}

# Function to clone or pull repository
git_operations() {
    log_info "Starting Git operations..."
    
    if [ -d "$CLONE_DIR" ]; then
        log_warning "Directory $CLONE_DIR exists. Pulling latest changes..."
        cd "$CLONE_DIR"
        
        # Configure Git for PAT authentication
        git config --local user.name "deployer"
        git config --local user.email "deployer@localhost"
        
        # Use PAT for authentication
        git remote set-url origin "https://oauth2:${PAT}@${GIT_REPO#https://}"
        git fetch origin
        
        # Check if branch exists
        if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
            git checkout "$BRANCH"
            git pull origin "$BRANCH"
        else
            git checkout -b "$BRANCH" "origin/$BRANCH"
        fi
    else
        log_info "Cloning repository..."
        # Insert PAT into repo URL for authentication
        local repo_with_token="https://oauth2:${PAT}@${GIT_REPO#https://}"
        git clone -b "$BRANCH" "$repo_with_token" "$CLONE_DIR"
        cd "$CLONE_DIR"
    fi
    
    log_success "Git operations completed successfully"
}

# Function to verify project structure
verify_project() {
    log_info "Verifying project structure..."
    
    if [ ! -f "Dockerfile" ] && [ ! -f "docker-compose.yml" ]; then
        log_error "No Dockerfile or docker-compose.yml found in project root"
        exit 1
    fi
    
    if [ -f "Dockerfile" ]; then
        log_success "Dockerfile found"
    fi
    
    if [ -f "docker-compose.yml" ]; then
        log_success "docker-compose.yml found"
    fi
    
    log_success "Project structure verified"
}

# Function to execute remote commands
execute_remote() {
    local command="$1"
    local description="$2"
    
    log_info "$description"
    
    if ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "${SSH_USER}@${SERVER_IP}" "$command"; then
        log_success "$description completed"
    else
        log_error "$description failed"
        exit 1
    fi
}

# Function to prepare remote environment
prepare_remote_environment() {
    log_info "Preparing remote environment..."
    
    # Update system and install dependencies
    execute_remote "
        sudo apt-get update && \
        sudo apt-get install -y curl gnupg lsb-release
    " "Updating package lists"
    
    # Install Docker
    execute_remote "
        if ! command -v docker &> /dev/null; then
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
            echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
            sudo apt-get update && \
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        else
            echo 'Docker already installed'
        fi
    " "Installing Docker"
    
    # Install Docker Compose
    execute_remote "
        if ! command -v docker-compose &> /dev/null; then
            sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose && \
            sudo chmod +x /usr/local/bin/docker-compose
        else
            echo 'Docker Compose already installed'
        fi
    " "Installing Docker Compose"
    
    # Install Nginx
    execute_remote "
        if ! command -v nginx &> /dev/null; then
            sudo apt-get install -y nginx
        else
            echo 'Nginx already installed'
        fi
    " "Installing Nginx"
    
    # Add user to docker group
    execute_remote "
        if ! groups $SSH_USER | grep -q '\bdocker\b'; then
            sudo usermod -aG docker $SSH_USER
        fi
    " "Adding user to docker group"
    
    # Start and enable services
    execute_remote "
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo systemctl enable nginx
        sudo systemctl start nginx
    " "Starting and enabling services"
    
    log_success "Remote environment preparation completed"
}

# Function to transfer project files
transfer_project() {
    log_info "Transferring project files to remote server..."
    
    # Create temporary archive
    local temp_archive="/tmp/${PROJECT_NAME}.tar.gz"
    tar -czf "$temp_archive" .
    
    # Transfer archive
    if scp -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$temp_archive" "${SSH_USER}@${SERVER_IP}:/tmp/"; then
        log_success "Project files transferred"
    else
        log_error "Failed to transfer project files"
        exit 1
    fi
    
    # Extract on remote server
    execute_remote "
        sudo mkdir -p /opt/$PROJECT_NAME && \
        sudo tar -xzf /tmp/${PROJECT_NAME}.tar.gz -C /opt/$PROJECT_NAME && \
        sudo chown -R $SSH_USER:$SSH_USER /opt/$PROJECT_NAME && \
        rm /tmp/${PROJECT_NAME}.tar.gz
    " "Extracting project files on remote server"
    
    # Clean up local archive
    rm "$temp_archive"
}

# Function to deploy application
deploy_application() {
    log_info "Deploying application..."
    
    execute_remote "
        cd /opt/$PROJECT_NAME && \
        if [ -f docker-compose.yml ]; then
            sudo docker-compose down || true
            sudo docker-compose up -d --build
        elif [ -f Dockerfile ]; then
            sudo docker stop $PROJECT_NAME || true
            sudo docker rm $PROJECT_NAME || true
            sudo docker build -t $PROJECT_NAME . && \
            sudo docker run -d --name $PROJECT_NAME -p 127.0.0.1:$APP_PORT:$APP_PORT $PROJECT_NAME
        fi
    " "Building and starting containers"
    
    # Wait for containers to be healthy
    log_info "Waiting for containers to be healthy..."
    sleep 30
    
    # Check container status
    execute_remote "
        if [ -f docker-compose.yml ]; then
            sudo docker-compose ps
        else
            sudo docker ps --filter \"name=$PROJECT_NAME\"
        fi
    " "Checking container status"
    
    log_success "Application deployment completed"
}

# Function to configure nginx
configure_nginx() {
    log_info "Configuring Nginx reverse proxy..."
    
    local nginx_config="/etc/nginx/sites-available/$PROJECT_NAME"
    local nginx_enabled="/etc/nginx/sites-enabled/$PROJECT_NAME"
    
    execute_remote "
sudo tee $nginx_config > /dev/null <<'NGINX_CONF'
server {
    listen 80;
    server_name $SERVER_IP;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX_CONF
sudo ln -sf $nginx_config $nginx_enabled
sudo nginx -t
sudo systemctl reload nginx
    " "Configuring Nginx reverse proxy"
    
    log_success "Nginx configuration completed"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check if container is running
    execute_remote "
        if [ -f docker-compose.yml ]; then
            sudo docker-compose ps | grep -q Up
        else
            sudo docker ps --filter \"name=$PROJECT_NAME\" --format 'table {{.Names}}\\t{{.Status}}' | grep -q Up
        fi
    " "Checking if container is running"
    
    # Check nginx status
    execute_remote "
        sudo systemctl is-active nginx
    " "Checking nginx status"
    
    # Test application endpoint
    log_info "Testing application endpoint..."
    if execute_remote "
        curl -f -s -o /dev/null -w \"%{http_code}\" http://localhost:$APP_PORT || \
        curl -f -s -o /dev/null -w \"%{http_code}\" http://localhost:80
    " "Testing application connectivity"; then
        log_success "Application is responding correctly"
    else
        log_warning "Application endpoint test failed, but deployment may still be successful"
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
show_summary() {
    echo
    echo -e "${GREEN}=== Deployment Summary ===${NC}"
    echo -e "${GREEN}✓ Deployment completed successfully${NC}"
    echo
    echo -e "${BLUE}Application Details:${NC}"
    echo -e "  Project: $PROJECT_NAME"
    echo -e "  Server: $SSH_USER@$SERVER_IP"
    echo -e "  URL: http://$SERVER_IP"
    echo -e "  Log file: $LOG_FILE"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "  1. Visit http://$SERVER_IP in your browser"
    echo -e "  2. Check logs: tail -f $LOG_FILE"
    echo -e "  3. Monitor containers: ssh -i $SSH_KEY_PATH $SSH_USER@$SERVER_IP 'docker ps'"
    echo
}

# Main execution function
main() {
    log_info "Starting deployment process..."
    log_info "Log file: $LOG_FILE"
    
    # Get user input
    get_user_input
    
    # Validate input
    validate_input
    
    # Local operations
    git_operations
    verify_project
    
    # Remote operations
    prepare_remote_environment
    transfer_project
    deploy_application
    configure_nginx
    validate_deployment
    
    # Show summary
    show_summary
    
    log_success "Deployment completed successfully!"
}

# Cleanup function for --cleanup flag
cleanup_deployment() {
    log_info "Starting cleanup..."
    
    execute_remote "
        cd /opt/$PROJECT_NAME && \
        if [ -f docker-compose.yml ]; then
            sudo docker-compose down
        else
            sudo docker stop $PROJECT_NAME || true
            sudo docker rm $PROJECT_NAME || true
        fi && \
        sudo rm -rf /opt/$PROJECT_NAME && \
        sudo rm -f /etc/nginx/sites-available/$PROJECT_NAME /etc/nginx/sites-enabled/$PROJECT_NAME && \
        sudo systemctl reload nginx
    " "Cleaning up deployment"
    
    log_success "Cleanup completed"
}

# Parse command line arguments
case "${1:-}" in
    --cleanup)
        get_user_input
        cleanup_deployment
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  --cleanup    Remove all deployed resources"
        echo "  --help, -h   Show this help message"
        echo ""
        echo "Example:"
        echo "  $0           # Run deployment"
        echo "  $0 --cleanup # Cleanup deployment"
        ;;
    *)
        main
        ;;
esac