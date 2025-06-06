#!/bin/bash

# Common functions and configuration loader for Rocky Linux 9 Ansible Lab
# This file should be sourced by other scripts

# Default configuration values
DEFAULT_CONFIG_FILE="config/lab.conf"
DEFAULT_SSH_KEY_PATH="/home/ubuntu/.ssh/id_rsa.pub"
DEFAULT_USER="rocky"

# VM names array
VMS=("controller" "worker1" "worker2")

# Load configuration from file
load_config() {
    local config_file="${1:-$DEFAULT_CONFIG_FILE}"
    
    if [ -f "$config_file" ]; then
        echo "Loading configuration from $config_file"
        # Source the config file, but only export variables we expect
        source "$config_file"
    elif [ -f "config/lab.conf.example" ]; then
        echo "No config file found, using defaults from example"
        source "config/lab.conf.example"
    else
        echo "No configuration file found, using built-in defaults"
    fi
    
    # Set defaults for any missing values
    DEPLOYMENT_TYPE="${DEPLOYMENT_TYPE:-kvm}"
    DEFAULT_USER="${DEFAULT_USER:-rocky}"
    DEFAULT_PASSWORD="${DEFAULT_PASSWORD:-rocky123}"
    SSH_KEY_PATH="${SSH_KEY_PATH:-$DEFAULT_SSH_KEY_PATH}"
    
    # KVM defaults
    KVM_STORAGE_PATH="${KVM_STORAGE_PATH:-/media/ubuntu/store/VMs}"
    KVM_MEMORY_SIZE="${KVM_MEMORY_SIZE:-4096}"
    KVM_VCPUS="${KVM_VCPUS:-2}"
    KVM_DISK_SIZE="${KVM_DISK_SIZE:-20}"
    
    # AWS defaults
    AWS_REGION="${AWS_REGION:-us-east-1}"
    AWS_INSTANCE_TYPE="${AWS_INSTANCE_TYPE:-t3.medium}"
    AWS_KEY_NAME="${AWS_KEY_NAME:-ansible-lab-key}"
    
    # Azure defaults
    AZURE_LOCATION="${AZURE_LOCATION:-eastus}"
    AZURE_VM_SIZE="${AZURE_VM_SIZE:-Standard_B2s}"
    AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-ansible-lab-rg}"
    AZURE_VNET_NAME="${AZURE_VNET_NAME:-ansible-lab-vnet}"
    AZURE_SUBNET_NAME="${AZURE_SUBNET_NAME:-ansible-lab-subnet}"
    AZURE_NSG_NAME="${AZURE_NSG_NAME:-ansible-lab-nsg}"
    AZURE_KEY_NAME="${AZURE_KEY_NAME:-ansible-lab-key}"
    
    # Network defaults
    NETWORK_CIDR="${NETWORK_CIDR:-10.0.0.0/16}"
    SUBNET_CIDR="${SUBNET_CIDR:-10.0.1.0/24}"
    
    # VM names
    VM_CONTROLLER="${VM_CONTROLLER:-controller}"
    VM_WORKER1="${VM_WORKER1:-worker1}"
    VM_WORKER2="${VM_WORKER2:-worker2}"
}

# Function to ensure SSH key exists
ensure_ssh_key() {
    local ssh_dir="/home/ubuntu/.ssh"
    local private_key="$ssh_dir/id_rsa"
    local public_key="$ssh_dir/id_rsa.pub"
    
    # Create .ssh directory if it doesn't exist
    if [ ! -d "$ssh_dir" ]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chown ubuntu:ubuntu "$ssh_dir"
    fi
    
    # Generate SSH key pair if it doesn't exist
    if [ ! -f "$private_key" ] || [ ! -f "$public_key" ]; then
        echo "SSH key pair not found. Generating new SSH key pair..."
        sudo -u ubuntu ssh-keygen -t rsa -b 4096 -f "$private_key" -N ""
        echo "✅ SSH key pair generated successfully"
    else
        echo "✅ SSH key pair already exists"
    fi
    
    # Update SSH_KEY_PATH to the actual location
    SSH_KEY_PATH="$public_key"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install required packages
install_package() {
    local package="$1"
    if ! command_exists "$package"; then
        echo "Installing $package..."
        sudo apt-get update && sudo apt-get install -y "$package"
    fi
}

# Function to generate cloud-init user data
generate_cloud_init_userdata() {
    local ssh_key_content
    ssh_key_content=$(cat "$SSH_KEY_PATH" 2>/dev/null || echo "")
    
    cat << EOF
#cloud-config
users:
  - name: $DEFAULT_USER
    groups: [wheel, adm, systemd-journal]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $ssh_key_content

# Set password for the user (optional, for console access)
chpasswd:
  list: |
    $DEFAULT_USER:$DEFAULT_PASSWORD
  expire: False

# Enable password authentication (optional)
ssh_pwauth: True

# Install basic packages
packages:
  - vim
  - git
  - htop
  - tree
  - curl
  - wget
  - python3
  - python3-pip

# Update system
package_update: true
package_upgrade: true

# Run commands to ensure proper setup
runcmd:
  - systemctl enable sshd
  - systemctl start sshd
  - usermod -aG wheel $DEFAULT_USER

# Final message
final_message: "Lab VM is ready for Ansible!"
EOF
}

# Function to generate Ansible inventory
generate_inventory() {
    local deployment_type="$1"
    local vm_ips=("${@:2}")
    
    cat > inventory.ini << EOF
# Auto-generated Ansible inventory for Rocky Linux 9 Lab
# Deployment type: $deployment_type
# Generated on: $(date)

[controllers]
${VM_CONTROLLER} ansible_host=${vm_ips[0]} ansible_user=$DEFAULT_USER ansible_ssh_private_key_file=/home/ubuntu/.ssh/id_rsa

[workers]
${VM_WORKER1} ansible_host=${vm_ips[1]} ansible_user=$DEFAULT_USER ansible_ssh_private_key_file=/home/ubuntu/.ssh/id_rsa
${VM_WORKER2} ansible_host=${vm_ips[2]} ansible_user=$DEFAULT_USER ansible_ssh_private_key_file=/home/ubuntu/.ssh/id_rsa

[lab:children]
controllers
workers

[lab:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_python_interpreter=/usr/bin/python3
EOF
    
    echo "✅ Ansible inventory generated: inventory.ini"
}

# Function to test SSH connectivity
test_ssh_connectivity() {
    local host="$1"
    local user="$2"
    local max_attempts=30
    local attempt=1
    
    echo "Testing SSH connectivity to $host..."
    
    while [ $attempt -le $max_attempts ]; do
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           "$user@$host" "echo 'SSH connection successful'" >/dev/null 2>&1; then
            echo "✅ SSH connection to $host successful"
            return 0
        fi
        
        echo "Attempt $attempt/$max_attempts failed, retrying in 10 seconds..."
        sleep 10
        ((attempt++))
    done
    
    echo "❌ Failed to establish SSH connection to $host after $max_attempts attempts"
    return 1
}

# Function to wait for all VMs to be ready
wait_for_vms() {
    local vm_ips=("$@")
    
    echo "Waiting for all VMs to be ready..."
    
    for ip in "${vm_ips[@]}"; do
        if ! test_ssh_connectivity "$ip" "$DEFAULT_USER"; then
            echo "❌ VM at $ip is not ready"
            return 1
        fi
    done
    
    echo "✅ All VMs are ready and accessible via SSH"
}

# Function to run Ansible ping test
test_ansible_connectivity() {
    echo "Testing Ansible connectivity..."
    
    if ansible all -i inventory.ini -m ping >/dev/null 2>&1; then
        echo "✅ Ansible connectivity test passed"
        return 0
    else
        echo "❌ Ansible connectivity test failed"
        return 1
    fi
}

# Function to display cost information for cloud deployments
show_cost_info() {
    local provider="$1"
    
    case "$provider" in
        aws)
            echo "💰 AWS Cost Information:"
            echo "   Instance Type: $AWS_INSTANCE_TYPE"
            echo "   Estimated Cost: ~\$0.125/hour for all 3 instances"
            echo "   Daily Cost: ~\$3.00/day if left running"
            echo "   Monthly Cost: ~\$90/month if left running"
            echo "   ⚠️  Remember to run cleanup when done!"
            ;;
        azure)
            echo "💰 Azure Cost Information:"
            echo "   VM Size: $AZURE_VM_SIZE"
            echo "   Estimated Cost: ~\$0.10/hour for all 3 VMs"
            echo "   Daily Cost: ~\$2.40/day if left running"
            echo "   Monthly Cost: ~\$72/month if left running"
            echo "   ⚠️  Remember to run cleanup when done!"
            ;;
    esac
}

# Function to print colored output
print_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "success")
            echo "✅ $message"
            ;;
        "error")
            echo "❌ $message"
            ;;
        "warning")
            echo "⚠️  $message"
            ;;
        "info")
            echo "ℹ️  $message"
            ;;
        *)
            echo "$message"
            ;;
    esac
} 