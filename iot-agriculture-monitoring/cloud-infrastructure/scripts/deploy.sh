#!/bin/bash
# cloud-infrastructure/scripts/deploy.sh

set -e

# Configuration
HEALTH_CHECK_TIMEOUT=120
PROJECT_NAME="iot-agriculture"
REMOTE_TEMP_DIR="/tmp/${PROJECT_NAME}-temp"
REMOTE_INSTALL_DIR="/opt/${PROJECT_NAME}"
BACKUP_DIR="${REMOTE_INSTALL_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
SSH_KEY="~/.oci/oci_api_key.pem"
SSH_OPTIONS="-i $SSH_KEY -o StrictHostKeyChecking=no"

echo "Deploying IoT Agriculture Monitoring System..."

# Check if required tools are installed
command -v docker-compose >/dev/null 2>&1 || { echo "docker-compose is required but not installed. Aborting." >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "terraform is required but not installed. Aborting." >&2; exit 1; }

# Check if SSH key exists
if [ ! -f "${SSH_KEY/#\~/$HOME}" ]; then
    echo "SSH key not found at $SSH_KEY. Aborting."
    exit 1
fi

# Create temporary directory for project files
echo "Preparing project files..."
LOCAL_TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$LOCAL_TEMP_DIR"' EXIT

# Copy project files to temporary directory, excluding unnecessary files
rsync -av --progress \
    --exclude='.git' \
    --exclude='.gitignore' \
    --exclude='node_modules' \
    --exclude='__pycache__' \
    --exclude='.env' \
    --exclude='*.pyc' \
    --exclude='.terraform' \
    --exclude='terraform.tfstate*' \
    --exclude='.DS_Store' \
    . "$LOCAL_TEMP_DIR"

# Deploy Terraform infrastructure
echo "Deploying OCI infrastructure..."
cd cloud-infrastructure/terraform
terraform init -upgrade
terraform plan -var-file="terraform.tfvars"
terraform apply -auto-approve -var-file="terraform.tfvars"

# Get outputs
INSTANCE_IP=$(terraform output -raw public_ip)
BUCKET_NAME=$(terraform output -raw bucket_name)
VAULT_ID=$(terraform output -raw vault_id)

echo "Infrastructure deployed successfully!"
echo "Instance IP: $INSTANCE_IP"
echo "Bucket Name: $BUCKET_NAME"
echo "Vault ID: $VAULT_ID"

# Wait for instance to be ready
echo "Waiting for instance to be ready..."
timeout 300 bash -c "until nc -z $INSTANCE_IP 22; do sleep 5; done" || {
    echo "Timeout waiting for instance SSH to be ready"
    exit 1
}

# Copy project files to instance
echo "Copying project files to instance..."
ssh $SSH_OPTIONS ubuntu@$INSTANCE_IP "sudo rm -rf $REMOTE_TEMP_DIR && mkdir -p $REMOTE_TEMP_DIR"
scp $SSH_OPTIONS -r "$LOCAL_TEMP_DIR"/* ubuntu@$INSTANCE_IP:$REMOTE_TEMP_DIR/

# Copy OCI configuration
echo "Copying OCI configuration..."
ssh $SSH_OPTIONS ubuntu@$INSTANCE_IP "mkdir -p ~/.oci"
scp $SSH_OPTIONS ~/.oci/* ubuntu@$INSTANCE_IP:~/.oci/

# First SSH session to setup Docker and permissions
echo "Setting up Docker and initial configuration..."
ssh $SSH_OPTIONS ubuntu@$INSTANCE_IP << 'ENDSSH1'
    set -e

    # Define variables in remote session
    PROJECT_NAME="iot-agriculture"
    REMOTE_TEMP_DIR="/tmp/${PROJECT_NAME}-temp"
    REMOTE_INSTALL_DIR="/opt/${PROJECT_NAME}"

    # Function to handle stuck apt processes
    handle_apt_locks() {
        echo "Checking for stuck apt/dpkg processes..."
        
        # List of lock files to check
        local lock_files=(
            "/var/lib/dpkg/lock"
            "/var/lib/apt/lists/lock"
            "/var/lib/dpkg/lock-frontend"
            "/var/cache/apt/archives/lock"
        )

        # Check each lock file
        for lock_file in "${lock_files[@]}"; do
            if [ -f "$lock_file" ]; then
                echo "Found lock file: $lock_file"
                local pid=$(sudo fuser "$lock_file" 2>/dev/null)
                if [ ! -z "$pid" ]; then
                    echo "Process $pid is holding the lock $lock_file"
                    local process_name=$(ps -p "$pid" -o comm=)
                    if [[ "$process_name" == *"apt"* ]] || [[ "$process_name" == *"dpkg"* ]]; then
                        echo "Found stuck apt/dpkg process $pid ($process_name). Attempting to kill it..."
                        sudo kill -9 "$pid" || true
                        sleep 2
                    fi
                fi
                echo "Removing lock file: $lock_file"
                sudo rm -f "$lock_file"
            fi
        done

        # Clean up partial packages
        if [ -d "/var/lib/dpkg/updates" ]; then
            echo "Cleaning up dpkg updates directory..."
            sudo rm -f /var/lib/dpkg/updates/*
        fi
        
        echo "Reconfiguring dpkg..."
        sudo dpkg --configure -a

        echo "Finishing apt setup..."
        sudo apt-get install -f

        return 0
    }

    # Function to wait for apt lock to be released
    wait_for_apt_lock() {
        local max_attempts=12  # Maximum number of attempts (1 minute total)
        local attempt=1
        
        while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
            echo "Waiting for apt locks to be released... Attempt $attempt of $max_attempts"
            sleep 5
            attempt=$((attempt + 1))
            
            if [ $attempt -gt $max_attempts ]; then
                echo "Lock still held after 1 minute. Attempting to fix stuck processes..."
                handle_apt_locks
                return 0
            fi
        done
        return 0
    }

    # Setup project directory
    echo "Setting up project directory..."
    sudo mkdir -p "$REMOTE_INSTALL_DIR"
    sudo cp -r "$REMOTE_TEMP_DIR"/* "$REMOTE_INSTALL_DIR"/
    sudo rm -rf "$REMOTE_TEMP_DIR"
    sudo chown -R ubuntu:ubuntu "$REMOTE_INSTALL_DIR"
    cd "$REMOTE_INSTALL_DIR"

    # Stop unattended upgrades
    echo "Stopping unattended upgrades..."
    sudo systemctl stop unattended-upgrades.service || true
    
    # Install Docker if not installed
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        
        # Wait for apt locks before proceeding
        echo "Checking apt locks..."
        wait_for_apt_lock || {
            echo "Failed to handle apt locks. Attempting aggressive cleanup..."
            handle_apt_locks
        }
        
        # Update package list
        sudo apt-get update
        
        # Install prerequisites
        sudo apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release
            
        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        # Set up the stable repository
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
          
        # Update package list again and install Docker
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    fi

    # Configure Docker permissions
    echo "Configuring Docker permissions..."
    sudo usermod -aG docker ubuntu
    sudo systemctl restart docker
    
    # Install Docker Compose if not installed
    if ! command -v docker-compose &> /dev/null; then
        echo "Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi

    # Restart unattended upgrades
    echo "Restarting unattended upgrades..."
    sudo systemctl start unattended-upgrades.service || true
ENDSSH1

# Second SSH session with new group membership
echo "Starting services with new Docker permissions..."
ssh $SSH_OPTIONS ubuntu@$INSTANCE_IP << ENDSSH2
    set -e
    cd "$REMOTE_INSTALL_DIR"

    # Create .env file with cloud-specific configurations
    echo "Configuring environment variables..."
    cat > .env << EOF
MYSQL_HOST=mysql
MONGODB_HOST=mongodb
OCI_BUCKET_NAME="$BUCKET_NAME"
OCI_VAULT_ID="$VAULT_ID"
MYSQL_USER=iot_user
MYSQL_PASSWORD=example
CLOUD_ENDPOINT=http://$INSTANCE_IP:3000
CLOUD_DASHBOARD_URL=http://$INSTANCE_IP:8088
OCI_VAULT_SECRET=default-secret
API_GATEWAY_URL=http://api-gateway:3000
REDIS_HOST=redis
EOF

    # Export environment variables for docker-compose
    export COMPOSE_HTTP_TIMEOUT=300
    export CLOUD_ENDPOINT=http://$INSTANCE_IP:3000
    export CLOUD_DASHBOARD_URL=http://$INSTANCE_IP:8088
    export OCI_BUCKET_NAME="$BUCKET_NAME"
    export OCI_VAULT_ID="$VAULT_ID"

    # Stop existing containers and clean up
    echo "Cleaning up Docker resources..."
    sudo docker-compose down || true
    sudo docker system prune -f

    # Rebuild and start containers
    echo "Starting services..."
    sudo docker-compose build --no-cache dashboard api-gateway  # Rebuild dashboard and api-gateway
    sudo docker-compose up -d

    echo "Application deployed successfully!"
    echo "Services status:"
    sudo docker-compose ps
ENDSSH2

# Update local environment securely
echo "Updating local environment..."
{
    echo "MYSQL_HOST=$INSTANCE_IP"
    echo "MONGODB_HOST=$INSTANCE_IP"
    echo "OCI_BUCKET_NAME=$BUCKET_NAME"
    echo "OCI_VAULT_ID=$VAULT_ID"
    echo "MYSQL_USER=\${MYSQL_USER:-iot_user}"
    echo "MYSQL_PASSWORD=\${MYSQL_PASSWORD:-$(openssl rand -base64 32)}"
    echo "CLOUD_ENDPOINT=http://$INSTANCE_IP:3000"
    echo "CLOUD_DASHBOARD_URL=http://$INSTANCE_IP:8088"
    echo "OCI_VAULT_SECRET=\${OCI_VAULT_SECRET:-$(openssl rand -base64 32)}"
} > .env

echo "Deployment completed successfully!"
echo "API Endpoint: http://$INSTANCE_IP:3000"
echo "Dashboard: http://$INSTANCE_IP:8088"

# Save deployment info for rollback
echo "$INSTANCE_IP" > .last_deploy_ip
date +%Y%m%d_%H%M%S > .last_deploy_time