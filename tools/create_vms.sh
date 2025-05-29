#!/bin/bash

# Configuration variables
ISO_PATH="/media/ubuntu/store/ISOs/Rocky-9.5-x86_64-minimal.iso"
VM_STORAGE="/media/ubuntu/store/VMs"
MEMORY_SIZE=4096
VCPUS=2
DISK_SIZE=20
KS_FILE="rocky9.ks"

# Array of VM names
VMS=("controller" "worker1" "worker2")

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Create Rocky Linux 9 VMs for Ansible lab environment"
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

# Check if ISO exists
if [ ! -f "$ISO_PATH" ]; then
    echo "ISO file not found at $ISO_PATH"
    exit 1
fi

# Check if kickstart file exists
if [ ! -f "$KS_FILE" ]; then
    echo "Kickstart file not found: $KS_FILE"
    exit 1
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
        echo "VM $vm_name removed successfully"
    else
        echo "VM $vm_name does not exist, skipping removal"
    fi
}

# Function to create VM
create_vm() {
    local vm_name=$1
    local disk_path="$VM_STORAGE/${vm_name}.qcow2"

    echo "Creating VM: $vm_name"
    
    # Check if VM already exists
    if check_vm_exists "$vm_name"; then
        echo "VM $vm_name already exists. Skipping..."
        return
    fi

    virt-install \
        --name "$vm_name" \
        --memory "$MEMORY_SIZE" \
        --vcpus "$VCPUS" \
        --disk path="$disk_path",size="$DISK_SIZE",bus=virtio \
        --os-variant rocky9.0 \
        --location "$ISO_PATH" \
        --network network=default \
        --boot uefi \
        --features smm=on \
        --initrd-inject "$KS_FILE" \
        --extra-args "inst.ks=file:/$KS_FILE console=tty0 console=ttyS0,115200n8 inst.gpt" \
        --noautoconsole

    if [ $? -eq 0 ]; then
        echo "Successfully created VM: $vm_name"
    else
        echo "Failed to create VM: $vm_name"
    fi
}

# Main execution
echo "Starting VM creation process..."
echo "Using default NAT network (192.168.122.0/24)"

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

echo "VM creation process completed." 