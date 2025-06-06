#!/bin/bash

# Azure Rocky Linux 9 VM Creation Script
# This script creates Rocky Linux 9 VMs in Azure for Ansible lab environment

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common functions
source "$SCRIPT_DIR/common.sh"

# Load configuration
load_config

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Create Rocky Linux 9 VMs in Azure for Ansible lab environment"
    echo
    echo "This script will:"
    echo "  - Create resource group if it doesn't exist"
    echo "  - Create virtual network and subnet"
    echo "  - Create network security group with SSH access"
    echo "  - Upload SSH key to Azure if not present"
    echo "  - Launch 3 VMs (controller, worker1, worker2)"
    echo "  - Configure passwordless SSH and sudo access via cloud-init"
    echo "  - Generate Ansible inventory file automatically"
    echo "  - Test connectivity to ensure everything works"
    echo
    echo "Environment Variables (or set in config/lab.conf):"
    echo "  AZURE_LOCATION        Azure region (default: eastus)"
    echo "  AZURE_VM_SIZE         VM size (default: Standard_B2s)"
    echo "  AZURE_RESOURCE_GROUP  Resource group name (default: ansible-lab-rg)"
    echo
    echo "Options:"
    echo "  --clean    Delete existing VMs before creating new ones"
    echo "  --help     Show this help message"
    echo
    echo "Prerequisites:"
    echo "  - Azure CLI installed and logged in (az login)"
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
    print_status "info" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        print_status "error" "Azure CLI is not installed. Please install it first:"
        echo "   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
        exit 1
    fi
    
    # Check if jq is installed
    if ! command_exists jq; then
        print_status "info" "Installing jq..."
        install_package jq
    fi
    
    # Check Azure login status
    if ! az account show &> /dev/null; then
        print_status "error" "Not logged in to Azure. Please run:"
        echo "   az login"
        exit 1
    fi
    
    print_status "success" "Prerequisites check passed"
}

# Function to clean up existing VMs
cleanup_existing_vms() {
    if [ "$CLEAN_VMS" -eq 1 ]; then
        print_status "info" "Cleaning up existing VMs..."
        
        for vm_name in "${VMS[@]}"; do
            if az vm show --resource-group "$AZURE_RESOURCE_GROUP" --name "$vm_name" &> /dev/null; then
                print_status "info" "Deleting VM: $vm_name"
                az vm delete --resource-group "$AZURE_RESOURCE_GROUP" --name "$vm_name" --yes --no-wait
            fi
        done
        
        # Wait for deletions to complete
        print_status "info" "Waiting for VM deletions to complete..."
        sleep 30
    fi
}

# Function to create resource group
create_resource_group() {
    print_status "info" "Setting up Azure resource group..."
    
    if az group show --name "$AZURE_RESOURCE_GROUP" &> /dev/null; then
        print_status "success" "Resource group '$AZURE_RESOURCE_GROUP' already exists"
    else
        print_status "info" "Creating resource group '$AZURE_RESOURCE_GROUP'..."
        az group create --name "$AZURE_RESOURCE_GROUP" --location "$AZURE_LOCATION"
        print_status "success" "Resource group created"
    fi
}

# Function to create virtual network
create_virtual_network() {
    print_status "info" "Setting up virtual network..."
    
    # Create VNet if it doesn't exist
    if az network vnet show --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_VNET_NAME" &> /dev/null; then
        print_status "success" "Virtual network '$AZURE_VNET_NAME' already exists"
    else
        print_status "info" "Creating virtual network '$AZURE_VNET_NAME'..."
        az network vnet create \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --name "$AZURE_VNET_NAME" \
            --address-prefix "$NETWORK_CIDR" \
            --subnet-name "$AZURE_SUBNET_NAME" \
            --subnet-prefix "$SUBNET_CIDR"
        print_status "success" "Virtual network created"
    fi
}

# Function to create network security group
create_network_security_group() {
    print_status "info" "Setting up network security group..."
    
    if az network nsg show --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_NSG_NAME" &> /dev/null; then
        print_status "success" "Network security group '$AZURE_NSG_NAME' already exists"
    else
        print_status "info" "Creating network security group '$AZURE_NSG_NAME'..."
        az network nsg create \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --name "$AZURE_NSG_NAME"
        
        # Create SSH rule
        az network nsg rule create \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --nsg-name "$AZURE_NSG_NAME" \
            --name "SSH" \
            --protocol tcp \
            --priority 1001 \
            --destination-port-range 22 \
            --access allow
        
        print_status "success" "Network security group created with SSH access"
    fi
}

# Function to upload SSH key to Azure
upload_ssh_key() {
    print_status "info" "Checking SSH key in Azure..."
    
    if az sshkey show --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_KEY_NAME" &> /dev/null; then
        print_status "success" "SSH key '$AZURE_KEY_NAME' already exists in Azure"
    else
        print_status "info" "Uploading SSH key to Azure..."
        az sshkey create \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --name "$AZURE_KEY_NAME" \
            --public-key "@$SSH_KEY_PATH"
        print_status "success" "SSH key uploaded to Azure as '$AZURE_KEY_NAME'"
    fi
}

# Function to create a single VM
create_vm() {
    local vm_name="$1"
    local vm_index="$2"
    
    print_status "info" "Creating VM: $vm_name"
    
    # Generate cloud-init data
    local cloud_init_file="/tmp/cloud-init-$vm_name.yml"
    generate_cloud_init_userdata > "$cloud_init_file"
    
    # Create VM (using RHEL 9 which is compatible with Rocky Linux)
    az vm create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$vm_name" \
        --image "RedHat:RHEL:9-lvm-gen2:latest" \
        --size "$AZURE_VM_SIZE" \
        --admin-username "$DEFAULT_USER" \
        --ssh-key-values "$SSH_KEY_PATH" \
        --vnet-name "$AZURE_VNET_NAME" \
        --subnet "$AZURE_SUBNET_NAME" \
        --nsg "$AZURE_NSG_NAME" \
        --public-ip-sku Standard \
        --custom-data "$cloud_init_file" \
        --no-wait
    
    # Clean up temp file
    rm -f "$cloud_init_file"
}

# Function to create all VMs
create_all_vms() {
    print_status "info" "Creating all VMs..."
    
    # Create VMs in parallel
    for i in "${!VMS[@]}"; do
        create_vm "${VMS[$i]}" "$i"
    done
    
    print_status "info" "Waiting for all VMs to be created..."
    
    # Wait for all VMs to be running
    for vm_name in "${VMS[@]}"; do
        print_status "info" "Waiting for $vm_name to be running..."
        az vm wait --resource-group "$AZURE_RESOURCE_GROUP" --name "$vm_name" --created
        print_status "success" "$vm_name is now running"
    done
}

# Function to get VM IP addresses
get_vm_ips() {
    local vm_ips=()
    
    print_status "info" "Getting VM IP addresses..."
    
    for vm_name in "${VMS[@]}"; do
        local ip
        ip=$(az vm show \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --name "$vm_name" \
            --show-details \
            --query publicIps \
            --output tsv)
        
        if [ -n "$ip" ]; then
            vm_ips+=("$ip")
            print_status "success" "$vm_name: $ip"
        else
            print_status "error" "Could not get IP for $vm_name"
            return 1
        fi
    done
    
    # Return the array (this is a bit tricky in bash)
    printf '%s\n' "${vm_ips[@]}"
}

# Function to test the lab environment
test_lab() {
    print_status "info" "Testing lab environment..."
    
    # Test Ansible connectivity
    if test_ansible_connectivity; then
        print_status "success" "Lab environment is ready!"
        echo
        echo "You can now run Ansible playbooks:"
        echo "  ansible-playbook -i inventory.ini examples/basic-setup.yml"
        echo
        echo "Or test individual hosts:"
        echo "  ansible all -i inventory.ini -m ping"
        return 0
    else
        print_status "error" "Lab environment test failed"
        return 1
    fi
}

# Main execution
main() {
    echo "🚀 Azure Rocky Linux 9 Lab Environment Setup"
    echo "============================================="
    echo
    
    # Show cost information
    show_cost_info "azure"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Ensure SSH key exists
    ensure_ssh_key
    
    # Clean up existing VMs if requested
    cleanup_existing_vms
    
    # Create Azure infrastructure
    create_resource_group
    create_virtual_network
    create_network_security_group
    upload_ssh_key
    
    # Create VMs
    create_all_vms
    
    # Get VM IPs
    print_status "info" "Retrieving VM IP addresses..."
    mapfile -t VM_IPS < <(get_vm_ips)
    
    if [ ${#VM_IPS[@]} -ne ${#VMS[@]} ]; then
        print_status "error" "Failed to get all VM IP addresses"
        exit 1
    fi
    
    # Generate inventory
    generate_inventory "azure" "${VM_IPS[@]}"
    
    # Wait for VMs to be ready
    wait_for_vms "${VM_IPS[@]}"
    
    # Test the lab
    test_lab
    
    echo
    print_status "success" "Azure lab environment setup complete!"
    echo
    echo "VM Details:"
    for i in "${!VMS[@]}"; do
        echo "  ${VMS[$i]}: ${VM_IPS[$i]}"
    done
    echo
    echo "Next steps:"
    echo "  1. Test connectivity: ansible all -i inventory.ini -m ping"
    echo "  2. Run example playbook: ansible-playbook -i inventory.ini examples/basic-setup.yml"
    echo "  3. When done, cleanup: ./setup.sh azure-cleanup"
    echo
    show_cost_info "azure"
}

# Run main function
main "$@" 