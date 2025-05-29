#!/bin/bash

# AWS EC2 Rocky Linux 9 VM Creation Script
# This script creates Rocky Linux 9 EC2 instances for Ansible lab environment

# Configuration variables
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
KEY_NAME="${KEY_NAME:-ansible-lab-key}"
SECURITY_GROUP_NAME="ansible-lab-sg"
VPC_NAME="ansible-lab-vpc"

# Array of VM names
VMS=("controller" "worker1" "worker2")

# Default user configuration
DEFAULT_USER="rocky"
SSH_KEY_PATH="/home/ubuntu/.ssh/id_rsa.pub"

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Create Rocky Linux 9 EC2 instances for Ansible lab environment"
    echo
    echo "This script will:"
    echo "  - Create VPC and security group if they don't exist"
    echo "  - Upload SSH key to AWS if not present"
    echo "  - Launch 3 EC2 instances (controller, worker1, worker2)"
    echo "  - Configure passwordless SSH and sudo access via cloud-init"
    echo "  - Generate Ansible inventory file automatically"
    echo "  - Test connectivity to ensure everything works"
    echo
    echo "Environment Variables:"
    echo "  AWS_REGION        AWS region (default: us-east-1)"
    echo "  INSTANCE_TYPE     EC2 instance type (default: t3.medium)"
    echo "  KEY_NAME          AWS key pair name (default: ansible-lab-key)"
    echo
    echo "Options:"
    echo "  --clean    Terminate existing instances before creating new ones"
    echo "  --help     Show this help message"
    echo
    echo "Prerequisites:"
    echo "  - AWS CLI configured with appropriate credentials"
    echo "  - jq installed for JSON parsing"
}

# Process command line arguments
CLEAN_VMS=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_VMS=1
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        echo "❌ AWS CLI is not installed. Please install it first:"
        echo "   curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'"
        echo "   unzip awscliv2.zip && sudo ./aws/install"
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo "❌ jq is not installed. Installing..."
        sudo apt-get update && sudo apt-get install -y jq
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ AWS credentials not configured. Please run:"
        echo "   aws configure"
        exit 1
    fi
    
    echo "✅ Prerequisites check passed"
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
        echo "SSH key pair generated successfully"
    else
        echo "SSH key pair already exists"
    fi
}

# Function to upload SSH key to AWS
upload_ssh_key() {
    echo "Checking AWS key pair..."
    
    if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &> /dev/null; then
        echo "✅ Key pair '$KEY_NAME' already exists in AWS"
    else
        echo "Uploading SSH key to AWS..."
        aws ec2 import-key-pair \
            --key-name "$KEY_NAME" \
            --public-key-material fileb://"$SSH_KEY_PATH" \
            --region "$AWS_REGION"
        echo "✅ SSH key uploaded to AWS as '$KEY_NAME'"
    fi
}

# Function to create VPC and security group
setup_aws_infrastructure() {
    echo "Setting up AWS infrastructure..."
    
    # Check if VPC exists
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$VPC_NAME" \
        --query 'Vpcs[0].VpcId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        echo "Creating VPC..."
        VPC_ID=$(aws ec2 create-vpc \
            --cidr-block 10.0.0.0/16 \
            --query 'Vpc.VpcId' \
            --output text \
            --region "$AWS_REGION")
        
        aws ec2 create-tags \
            --resources "$VPC_ID" \
            --tags Key=Name,Value="$VPC_NAME" \
            --region "$AWS_REGION"
        
        # Create internet gateway
        IGW_ID=$(aws ec2 create-internet-gateway \
            --query 'InternetGateway.InternetGatewayId' \
            --output text \
            --region "$AWS_REGION")
        
        aws ec2 attach-internet-gateway \
            --vpc-id "$VPC_ID" \
            --internet-gateway-id "$IGW_ID" \
            --region "$AWS_REGION"
        
        # Create subnet
        SUBNET_ID=$(aws ec2 create-subnet \
            --vpc-id "$VPC_ID" \
            --cidr-block 10.0.1.0/24 \
            --query 'Subnet.SubnetId' \
            --output text \
            --region "$AWS_REGION")
        
        # Create route table and route
        ROUTE_TABLE_ID=$(aws ec2 create-route-table \
            --vpc-id "$VPC_ID" \
            --query 'RouteTable.RouteTableId' \
            --output text \
            --region "$AWS_REGION")
        
        aws ec2 create-route \
            --route-table-id "$ROUTE_TABLE_ID" \
            --destination-cidr-block 0.0.0.0/0 \
            --gateway-id "$IGW_ID" \
            --region "$AWS_REGION"
        
        aws ec2 associate-route-table \
            --subnet-id "$SUBNET_ID" \
            --route-table-id "$ROUTE_TABLE_ID" \
            --region "$AWS_REGION"
        
        echo "✅ VPC created: $VPC_ID"
    else
        echo "✅ VPC already exists: $VPC_ID"
        # Get subnet ID
        SUBNET_ID=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            --query 'Subnets[0].SubnetId' \
            --output text \
            --region "$AWS_REGION")
    fi
    
    # Check if security group exists
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" "Name=vpc-id,Values=$VPC_ID" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
        echo "Creating security group..."
        SG_ID=$(aws ec2 create-security-group \
            --group-name "$SECURITY_GROUP_NAME" \
            --description "Ansible lab security group" \
            --vpc-id "$VPC_ID" \
            --query 'GroupId' \
            --output text \
            --region "$AWS_REGION")
        
        # Add SSH rule
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0 \
            --region "$AWS_REGION"
        
        # Add rule for internal communication
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol -1 \
            --source-group "$SG_ID" \
            --region "$AWS_REGION"
        
        echo "✅ Security group created: $SG_ID"
    else
        echo "✅ Security group already exists: $SG_ID"
    fi
}

# Function to get Rocky Linux 9 AMI ID
get_rocky_ami() {
    echo "Finding Rocky Linux 9 AMI..."
    AMI_ID=$(aws ec2 describe-images \
        --owners 792107900819 \
        --filters "Name=name,Values=Rocky-9-EC2-Base-*" "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text \
        --region "$AWS_REGION")
    
    if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
        echo "❌ Could not find Rocky Linux 9 AMI"
        exit 1
    fi
    
    echo "✅ Found Rocky Linux 9 AMI: $AMI_ID"
}

# Function to create cloud-init user data
create_user_data() {
    local vm_name=$1
    
    cat << EOF
#cloud-config
hostname: $vm_name
fqdn: $vm_name.local

users:
  - name: $DEFAULT_USER
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat $SSH_KEY_PATH)

# Disable root login
disable_root: true
ssh_pwauth: false

# Package updates and installations
package_update: true
package_upgrade: false

packages:
  - vim
  - wget
  - curl
  - git
  - htop

# Configure SSH
ssh_deletekeys: true
ssh_genkeytypes: ['rsa', 'ecdsa', 'ed25519']

# Set timezone
timezone: America/New_York

# Final commands
runcmd:
  - systemctl enable sshd
  - systemctl start sshd
  - echo "Cloud-init setup completed for $vm_name" > /var/log/cloud-init-complete.log
EOF
}

# Function to terminate existing instances
cleanup_instances() {
    echo "Cleaning up existing instances..."
    
    for vm_name in "${VMS[@]}"; do
        INSTANCE_ID=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=$vm_name" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
            --query 'Reservations[0].Instances[0].InstanceId' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null)
        
        if [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then
            echo "Terminating instance: $vm_name ($INSTANCE_ID)"
            aws ec2 terminate-instances \
                --instance-ids "$INSTANCE_ID" \
                --region "$AWS_REGION" > /dev/null
        fi
    done
    
    # Wait for instances to terminate
    echo "Waiting for instances to terminate..."
    sleep 30
}

# Function to create EC2 instance
create_instance() {
    local vm_name=$1
    
    echo "Creating EC2 instance: $vm_name"
    
    # Create user data
    USER_DATA=$(create_user_data "$vm_name" | base64 -w 0)
    
    # Launch instance
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --count 1 \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --subnet-id "$SUBNET_ID" \
        --associate-public-ip-address \
        --user-data "$USER_DATA" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$vm_name}]" \
        --query 'Instances[0].InstanceId' \
        --output text \
        --region "$AWS_REGION")
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully created instance: $vm_name ($INSTANCE_ID)"
    else
        echo "❌ Failed to create instance: $vm_name"
        return 1
    fi
}

# Function to wait for instances and get IPs
wait_for_instances() {
    echo "Waiting for instances to be ready..."
    
    # Wait for all instances to be running
    for vm_name in "${VMS[@]}"; do
        echo "Waiting for $vm_name to be running..."
        aws ec2 wait instance-running \
            --filters "Name=tag:Name,Values=$vm_name" \
            --region "$AWS_REGION"
    done
    
    echo "✅ All instances are running"
}

# Function to generate Ansible inventory
generate_inventory() {
    echo "Generating Ansible inventory file..."
    local inventory_file="../inventory.ini"
    
    # Get IP addresses
    local controller_ip=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=controller" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --region "$AWS_REGION")
    
    local worker1_ip=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=worker1" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --region "$AWS_REGION")
    
    local worker2_ip=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=worker2" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --region "$AWS_REGION")
    
    # Create inventory file
    cat > "$inventory_file" << EOF
[controllers]
controller ansible_host=$controller_ip

[workers]
worker1 ansible_host=$worker1_ip
worker2 ansible_host=$worker2_ip

[rocky_lab:children]
controllers
workers

[rocky_lab:vars]
ansible_user=rocky
ansible_ssh_private_key_file=~/.ssh/id_rsa
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

# AWS-specific variables
[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF
    
    chown ubuntu:ubuntu "$inventory_file"
    echo "✅ Ansible inventory created: $inventory_file"
    echo "VM IP addresses:"
    echo "  controller: $controller_ip"
    echo "  worker1: $worker1_ip"
    echo "  worker2: $worker2_ip"
}

# Function to test connectivity
test_connectivity() {
    echo "Testing SSH connectivity and passwordless sudo..."
    
    # Wait for cloud-init to complete
    echo "Waiting for cloud-init to complete (60 seconds)..."
    sleep 60
    
    # Get IP addresses
    local controller_ip=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=controller" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --region "$AWS_REGION")
    
    local worker1_ip=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=worker1" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --region "$AWS_REGION")
    
    local worker2_ip=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=worker2" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --region "$AWS_REGION")
    
    # Test each VM
    for vm_name in controller worker1 worker2; do
        case $vm_name in
            controller) ip=$controller_ip ;;
            worker1) ip=$worker1_ip ;;
            worker2) ip=$worker2_ip ;;
        esac
        
        echo "Testing $vm_name ($ip)..."
        if sudo -u ubuntu ssh -o ConnectTimeout=30 -o StrictHostKeyChecking=no rocky@$ip "echo 'SSH works' && sudo whoami" &>/dev/null; then
            echo "  ✅ $vm_name: SSH and passwordless sudo working"
        else
            echo "  ❌ $vm_name: Connection failed (may need more time for cloud-init)"
        fi
    done
    
    echo ""
    echo "You can now test Ansible connectivity with:"
    echo "  ansible all -i inventory.ini -m ping"
}

# Main execution
echo "🚀 Starting AWS EC2 instance creation process..."
echo "Region: $AWS_REGION"
echo "Instance Type: $INSTANCE_TYPE"
echo "Key Name: $KEY_NAME"

# Check prerequisites
check_prerequisites

# Ensure SSH key exists for passwordless authentication
ensure_ssh_key

# Upload SSH key to AWS
upload_ssh_key

# Setup AWS infrastructure
setup_aws_infrastructure

# Get Rocky Linux AMI
get_rocky_ami

# Clean up existing instances if requested
if [ "$CLEAN_VMS" -eq 1 ]; then
    cleanup_instances
fi

# Create instances
for vm in "${VMS[@]}"; do
    create_instance "$vm"
done

# Wait for instances to be ready
wait_for_instances

# Generate Ansible inventory
generate_inventory

# Test connectivity
test_connectivity

echo "🎉 AWS EC2 instance creation completed successfully!"
echo "✅ 3 Rocky Linux 9 EC2 instances created with passwordless SSH and sudo"
echo "✅ Ansible inventory file generated: inventory.ini"
echo "✅ Ready for Ansible automation"
echo ""
echo "💰 Remember to terminate instances when done to avoid charges:"
echo "  ./setup.sh aws-clean" 