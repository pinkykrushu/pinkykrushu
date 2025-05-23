#!/bin/bash

# Create directories for security tools
sudo mkdir -p /opt/tanium
sudo mkdir -p /opt/crowdstrike
sudo mkdir -p /opt/qualys

# Function to download and stage Tanium Client
stage_tanium() {
    echo "Staging Tanium Client..."
    sudo mkdir -p /opt/tanium/staging
    # Download Tanium client package (replace with your actual download URL)
    # sudo curl -o /opt/tanium/staging/tanium.rpm "YOUR_TANIUM_DOWNLOAD_URL"
    
    # Remove any existing configuration
    sudo rm -rf /opt/tanium/TaniumClient
    sudo rm -f /etc/systemd/system/taniumclient.service
    sudo rm -f /etc/init.d/taniumclient
}

# Function to download and stage CrowdStrike Agent
stage_crowdstrike() {
    echo "Staging CrowdStrike Agent..."
    sudo mkdir -p /opt/crowdstrike/staging
    # Download CrowdStrike package (replace with your actual download URL)
    # sudo curl -o /opt/crowdstrike/staging/falcon-sensor.rpm "YOUR_CROWDSTRIKE_DOWNLOAD_URL"
    
    # Remove any existing configuration
    sudo rm -rf /opt/CrowdStrike
    sudo systemctl disable falcon-sensor 2>/dev/null || true
    sudo rm -f /etc/systemd/system/falcon-sensor.service
}

# Function to download and stage Qualys Agent
stage_qualys() {
    echo "Staging Qualys Agent..."
    sudo mkdir -p /opt/qualys/staging
    # Download Qualys package (replace with your actual download URL)
    # sudo curl -o /opt/qualys/staging/qualys-agent.rpm "YOUR_QUALYS_DOWNLOAD_URL"
    
    # Remove any existing configuration
    sudo rm -rf /usr/local/qualys
    sudo systemctl disable qualys-cloud-agent 2>/dev/null || true
    sudo rm -f /etc/systemd/system/qualys-cloud-agent.service
}

# Stage all security tools
stage_tanium
stage_crowdstrike
stage_qualys

# Create directories for cloud-init scripts
sudo mkdir -p /var/lib/cloud/scripts/per-instance
sudo mkdir -p /var/lib/cloud/scripts/examples

# Create cloud-init script for security tools configuration
cat << 'EOF' | sudo tee /var/lib/cloud/scripts/per-instance/configure-security-tools.sh
#!/bin/bash

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a /var/log/security-tools-setup.log
}

# Configure and start Tanium Client
configure_tanium() {
    log_message "Configuring Tanium Client..."
    # Get instance metadata
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    
    # Get Tanium configuration from SSM Parameter Store
    TANIUM_SERVER=$(aws ssm get-parameter --name "/security/tanium/server" --region $REGION --with-decryption --query "Parameter.Value" --output text)
    TANIUM_KEY=$(aws ssm get-parameter --name "/security/tanium/key" --region $REGION --with-decryption --query "Parameter.Value" --output text)
    
    if [ -n "$TANIUM_SERVER" ] && [ -n "$TANIUM_KEY" ]; then
        # Install Tanium package
        if [ -f /opt/tanium/staging/tanium.rpm ]; then
            sudo rpm -ivh /opt/tanium/staging/tanium.rpm
            sudo /opt/tanium/TaniumClient/TaniumClient config set ServerName "$TANIUM_SERVER"
            sudo /opt/tanium/TaniumClient/TaniumClient config set ServerPort 17472
            sudo /opt/tanium/TaniumClient/TaniumClient config set LogVerbosityLevel 1
            sudo systemctl enable taniumclient
            sudo systemctl start taniumclient
            log_message "Tanium Client installed and configured successfully"
        else
            log_message "Error: Tanium package not found in staging directory"
        fi
    else
        log_message "Error: Missing Tanium configuration parameters"
    fi
}

# Configure and start CrowdStrike Agent
configure_crowdstrike() {
    log_message "Configuring CrowdStrike Agent..."
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    CS_CID=$(aws ssm get-parameter --name "/security/crowdstrike/cid" --region $REGION --with-decryption --query "Parameter.Value" --output text)
    
    if [ -n "$CS_CID" ]; then
        if [ -f /opt/crowdstrike/staging/falcon-sensor.rpm ]; then
            sudo rpm -ivh /opt/crowdstrike/staging/falcon-sensor.rpm
            sudo /opt/CrowdStrike/falconctl -s --cid="$CS_CID"
            sudo systemctl enable falcon-sensor
            sudo systemctl start falcon-sensor
            log_message "CrowdStrike Agent installed and configured successfully"
        else
            log_message "Error: CrowdStrike package not found in staging directory"
        fi
    else
        log_message "Error: Missing CrowdStrike configuration parameters"
    fi
}

# Configure and start Qualys Cloud Agent
configure_qualys() {
    log_message "Configuring Qualys Cloud Agent..."
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    QUALYS_ID=$(aws ssm get-parameter --name "/security/qualys/id" --region $REGION --with-decryption --query "Parameter.Value" --output text)
    QUALYS_KEY=$(aws ssm get-parameter --name "/security/qualys/key" --region $REGION --with-decryption --query "Parameter.Value" --output text)
    
    if [ -n "$QUALYS_ID" ] && [ -n "$QUALYS_KEY" ]; then
        if [ -f /opt/qualys/staging/qualys-agent.rpm ]; then
            sudo rpm -ivh /opt/qualys/staging/qualys-agent.rpm
            sudo /usr/local/qualys/cloud-agent/bin/qualys-cloud-agent.sh ActivationId="$QUALYS_ID" CustomerId="$QUALYS_KEY"
            sudo systemctl enable qualys-cloud-agent
            sudo systemctl start qualys-cloud-agent
            log_message "Qualys Cloud Agent installed and configured successfully"
        else
            log_message "Error: Qualys package not found in staging directory"
        fi
    else
        log_message "Error: Missing Qualys configuration parameters"
    fi
}

# Main execution
log_message "Starting security tools configuration"

# Configure each tool
configure_tanium
configure_crowdstrike
configure_qualys

log_message "Security tools configuration completed"
EOF

# Make the cloud-init script executable
sudo chmod +x /var/lib/cloud/scripts/per-instance/configure-security-tools.sh

# Create cloud-init user-data template
cat << 'EOF' | sudo tee /var/lib/cloud/scripts/examples/security-tools-userdata.sh
#!/bin/bash
# This is a template for the user-data script that should be used when launching instances

# Install AWS CLI if not present
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
fi

# Ensure the security tools configuration script is executable
chmod +x /var/lib/cloud/scripts/per-instance/configure-security-tools.sh

# Run the configuration script
/var/lib/cloud/scripts/per-instance/configure-security-tools.sh
EOF

# Set appropriate permissions
sudo chmod 644 /var/lib/cloud/scripts/examples/security-tools-userdata.sh

# Create a cleanup script to run during instance shutdown
cat << 'EOF' | sudo tee /usr/local/bin/cleanup-security-tools.sh
#!/bin/bash

# Stop and disable services
systemctl stop taniumclient falcon-sensor qualys-cloud-agent
systemctl disable taniumclient falcon-sensor qualys-cloud-agent

# Remove configuration files
rm -rf /opt/tanium/TaniumClient/Tools
rm -f /opt/tanium/TaniumClient/*.conf
rm -rf /opt/CrowdStrike/Config
rm -rf /usr/local/qualys/cloud-agent/Config

# Clear logs
rm -f /opt/tanium/TaniumClient/logs/*
rm -f /var/log/crowdstrike/*
rm -f /var/log/qualys/*
EOF

sudo chmod +x /usr/local/bin/cleanup-security-tools.sh 