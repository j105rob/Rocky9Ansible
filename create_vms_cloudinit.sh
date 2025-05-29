#!/bin/bash

# Configuration variables
BASE_IMAGE="/media/ubuntu/store/VMs/rocky9-cloud-base.qcow2"
VM_STORAGE="/media/ubuntu/store/VMs"
MEMORY_SIZE=4096
VCPUS=2
DISK_SIZE=20

# Array of VM names
VMS=("controller" "worker1" "worker2")

# Default user configuration
DEFAULT_USER="rocky"
DEFAULT_PASSWORD="rocky123"
SSH_KEY_PATH="/home/ubuntu/.ssh/id_rsa.pub"

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Create Rocky Linux 9 VMs using cloud-init for Ansible lab environment"
    echo
    echo "This script will:"
    echo "  - Generate SSH key pair if not present (for passwordless SSH)"
    echo "  - Create 3 VMs with cloud-init (controller, worker1, worker2)"
    echo "  - Configure passwordless SSH and sudo access"
    echo "  - Generate Ansible inventory file automatically"
    echo "  - Test connectivity to ensure everything works"
    echo
    echo "Options:"
    echo "  --clean    Remove existing VMs before creating new ones"
    echo "  --help     Show this help message"
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Check if base image exists
if [ ! -f "$BASE_IMAGE" ]; then
    echo "Base cloud image not found at $BASE_IMAGE"
    echo "Please run build_rocky9_image.sh first to create the base image"
    exit 1
fi

# Check if genisoimage is installed
if ! command -v genisoimage &> /dev/null; then
    echo "genisoimage is required but not installed. Installing..."
    apt-get update && apt-get install -y genisoimage
fi

# Ensure default network is active
if ! virsh net-info default >/dev/null 2>&1; then
    echo "Creating default network..."
    virsh net-define /usr/share/libvirt/networks/default.xml
    virsh net-autostart default
fi
if ! virsh net-list | grep -q "default.*active"; then
    echo "Starting default network..."
    virsh net-start default
fi

# Create VM storage directory if it doesn't exist
mkdir -p "$VM_STORAGE"
mkdir -p "$VM_STORAGE/cloud-init"

# Function to check if VM exists
check_vm_exists() {
    virsh dominfo "$1" &> /dev/null
    return $?
}

# Function to remove VM
remove_vm() {
    local vm_name=$1
    echo "Removing VM: $vm_name"
    
    # Check if VM exists before trying to remove it
    if check_vm_exists "$vm_name"; then
        # Stop the VM if it's running
        virsh destroy "$vm_name" &> /dev/null || true
        sleep 2
        # Remove the VM including NVRAM file
        virsh undefine "$vm_name" --nvram || true
        # Manually remove the storage
        rm -f "$VM_STORAGE/${vm_name}.qcow2"
        rm -rf "$VM_STORAGE/cloud-init/${vm_name}"
        echo "VM $vm_name removed successfully"
    else
        echo "VM $vm_name does not exist, skipping removal"
    fi
}

# Function to create cloud-init data
create_cloud_init() {
    local vm_name=$1
    local cloud_init_dir="$VM_STORAGE/cloud-init/$vm_name"
    
    mkdir -p "$cloud_init_dir"
    
    # Generate password hash
    local password_hash=$(openssl passwd -6 "$DEFAULT_PASSWORD")
    
    # Generate SSH key section if key exists
    local ssh_key_section=""
    if [ -f "$SSH_KEY_PATH" ]; then
        ssh_key_section="    ssh_authorized_keys:
      - $(cat $SSH_KEY_PATH)"
    fi
    
    # Create user-data
    cat > "$cloud_init_dir/user-data" << EOF
#cloud-config
hostname: $vm_name
fqdn: $vm_name.local

users:
  - name: $DEFAULT_USER
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $password_hash
$ssh_key_section

# Disable root login
disable_root: true
ssh_pwauth: true

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

# Configure network (DHCP)
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true

# Final commands
runcmd:
  - systemctl enable sshd
  - systemctl start sshd
  - echo "Cloud-init setup completed for $vm_name" > /var/log/cloud-init-complete.log

# Power state
power_state:
  mode: reboot
  delay: 1
  timeout: 30
  condition: true
EOF

    # Create meta-data
    cat > "$cloud_init_dir/meta-data" << EOF
instance-id: $vm_name-$(date +%s)
local-hostname: $vm_name
EOF

    # Create cloud-init ISO
    genisoimage -output "$cloud_init_dir/$vm_name-cloud-init.iso" \
        -volid cidata -joliet -rock \
        "$cloud_init_dir/user-data" \
        "$cloud_init_dir/meta-data"
    
    # Set proper ownership
    chown -R libvirt-qemu:libvirt-qemu "$cloud_init_dir"
}

# Function to create VM
create_vm() {
    local vm_name=$1
    local disk_path="$VM_STORAGE/${vm_name}.qcow2"
    local cloud_init_iso="$VM_STORAGE/cloud-init/$vm_name/$vm_name-cloud-init.iso"

    echo "Creating VM: $vm_name"
    
    # Check if VM already exists
    if check_vm_exists "$vm_name"; then
        echo "VM $vm_name already exists. Skipping..."
        return
    fi

    # Create cloud-init data
    create_cloud_init "$vm_name"

    # Create VM disk from base image
    qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$disk_path" "${DISK_SIZE}G"
    chown libvirt-qemu:libvirt-qemu "$disk_path"

    virt-install \
        --name "$vm_name" \
        --memory "$MEMORY_SIZE" \
        --vcpus "$VCPUS" \
        --disk path="$disk_path",bus=virtio \
        --disk path="$cloud_init_iso",device=cdrom \
        --os-variant rocky9.0 \
        --network network=default \
        --boot uefi \
        --features smm=on \
        --noautoconsole \
        --import

    if [ $? -eq 0 ]; then
        echo "Successfully created VM: $vm_name"
    else
        echo "Failed to create VM: $vm_name"
    fi
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

# Function to generate Ansible inventory
generate_inventory() {
    echo "Generating Ansible inventory file..."
    local inventory_file="inventory.ini"
    
    # Wait a moment for VMs to get IP addresses
    sleep 10
    
    # Get IP addresses
    local controller_ip=$(virsh domifaddr controller | grep -o '192\.168\.122\.[0-9]*' | head -1)
    local worker1_ip=$(virsh domifaddr worker1 | grep -o '192\.168\.122\.[0-9]*' | head -1)
    local worker2_ip=$(virsh domifaddr worker2 | grep -o '192\.168\.122\.[0-9]*' | head -1)
    
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
EOF
    
    chown ubuntu:ubuntu "$inventory_file"
    echo "Ansible inventory created: $inventory_file"
    echo "VM IP addresses:"
    echo "  controller: $controller_ip"
    echo "  worker1: $worker1_ip"
    echo "  worker2: $worker2_ip"
}

# Function to test connectivity
test_connectivity() {
    echo "Testing SSH connectivity and passwordless sudo..."
    
    # Wait for VMs to complete cloud-init setup
    echo "Waiting for cloud-init to complete (30 seconds)..."
    sleep 30
    
    # Get IP addresses
    local controller_ip=$(virsh domifaddr controller | grep -o '192\.168\.122\.[0-9]*' | head -1)
    local worker1_ip=$(virsh domifaddr worker1 | grep -o '192\.168\.122\.[0-9]*' | head -1)
    local worker2_ip=$(virsh domifaddr worker2 | grep -o '192\.168\.122\.[0-9]*' | head -1)
    
    # Test each VM
    for vm_name in controller worker1 worker2; do
        case $vm_name in
            controller) ip=$controller_ip ;;
            worker1) ip=$worker1_ip ;;
            worker2) ip=$worker2_ip ;;
        esac
        
        echo "Testing $vm_name ($ip)..."
        if sudo -u ubuntu ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no rocky@$ip "echo 'SSH works' && sudo whoami" &>/dev/null; then
            echo "  ✅ $vm_name: SSH and passwordless sudo working"
        else
            echo "  ❌ $vm_name: Connection failed"
        fi
    done
    
    echo ""
    echo "You can now test Ansible connectivity with:"
    echo "  ansible all -i inventory.ini -m ping"
}

# Main execution
echo "Starting VM creation process using cloud-init..."
echo "Using default NAT network (192.168.122.0/24)"

# Ensure SSH key exists for passwordless authentication
ensure_ssh_key

# Clean up existing VMs if requested
if [ "$CLEAN_VMS" -eq 1 ]; then
    echo "Cleaning up existing VMs..."
    for vm in "${VMS[@]}"; do
        remove_vm "$vm"
    done
fi

# Create VMs
for vm in "${VMS[@]}"; do
    create_vm "$vm"
done

# Generate Ansible inventory
generate_inventory

# Test connectivity
test_connectivity

echo "🎉 VM creation process completed successfully!"
echo "✅ 3 Rocky Linux 9 VMs created with passwordless SSH and sudo"
echo "✅ Ansible inventory file generated: inventory.ini"
echo "✅ Ready for Ansible automation"
echo ""
echo "VMs will reboot once after cloud-init completes initial setup." 