#!/bin/bash

# Azure Resource Cleanup Script
# This script removes all Azure resources created for the Rocky Linux 9 Ansible lab

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
    echo "Clean up all Azure resources for Rocky Linux 9 Ansible lab"
    echo
    echo "This script will remove:"
    echo "  - All VMs (controller, worker1, worker2)"
    echo "  - Network interfaces and public IPs"
    echo "  - Network security group"
    echo "  - Virtual network and subnet"
    echo "  - SSH key"
    echo "  - Resource group (if --delete-rg is specified)"
    echo
    echo "Options:"
    echo "  --delete-rg    Also delete the entire resource group"
    echo "  --force        Skip confirmation prompts"
    echo "  --help         Show this help message"
    echo
    echo "Environment Variables (or set in config/lab.conf):"
    echo "  AZURE_RESOURCE_GROUP  Resource group name (default: ansible-lab-rg)"
}

# Process command line arguments
DELETE_RG=0
FORCE=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --delete-rg)
            DELETE_RG=1
            shift
            ;;
        --force)
            FORCE=1
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
        print_status "error" "Azure CLI is not installed"
        exit 1
    fi
    
    # Check Azure login status
    if ! az account show &> /dev/null; then
        print_status "error" "Not logged in to Azure. Please run: az login"
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "$AZURE_RESOURCE_GROUP" &> /dev/null; then
        print_status "warning" "Resource group '$AZURE_RESOURCE_GROUP' does not exist"
        print_status "info" "Nothing to clean up"
        exit 0
    fi
    
    print_status "success" "Prerequisites check passed"
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$FORCE" -eq 1 ]; then
        return 0
    fi
    
    echo
    print_status "warning" "This will delete the following Azure resources:"
    echo "  - Resource Group: $AZURE_RESOURCE_GROUP"
    echo "  - All VMs: ${VMS[*]}"
    echo "  - All associated network resources"
    echo "  - SSH keys"
    
    if [ "$DELETE_RG" -eq 1 ]; then
        echo "  - The entire resource group will be deleted"
    fi
    
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "info" "Cleanup cancelled"
        exit 0
    fi
}

# Function to delete VMs
delete_vms() {
    print_status "info" "Deleting VMs..."
    
    local vms_found=0
    for vm_name in "${VMS[@]}"; do
        if az vm show --resource-group "$AZURE_RESOURCE_GROUP" --name "$vm_name" &> /dev/null; then
            print_status "info" "Deleting VM: $vm_name"
            az vm delete --resource-group "$AZURE_RESOURCE_GROUP" --name "$vm_name" --yes --no-wait
            vms_found=1
        else
            print_status "info" "VM $vm_name not found (already deleted or never created)"
        fi
    done
    
    if [ $vms_found -eq 1 ]; then
        print_status "info" "Waiting for VM deletions to complete..."
        sleep 30
        print_status "success" "All VMs deleted"
    else
        print_status "info" "No VMs found to delete"
    fi
}

# Function to delete network interfaces
delete_network_interfaces() {
    print_status "info" "Deleting network interfaces..."
    
    local nics
    nics=$(az network nic list --resource-group "$AZURE_RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
    
    if [ -n "$nics" ]; then
        while IFS= read -r nic_name; do
            if [ -n "$nic_name" ]; then
                print_status "info" "Deleting network interface: $nic_name"
                az network nic delete --resource-group "$AZURE_RESOURCE_GROUP" --name "$nic_name" --no-wait
            fi
        done <<< "$nics"
        
        print_status "info" "Waiting for network interface deletions to complete..."
        sleep 15
        print_status "success" "Network interfaces deleted"
    else
        print_status "info" "No network interfaces found to delete"
    fi
}

# Function to delete public IPs
delete_public_ips() {
    print_status "info" "Deleting public IP addresses..."
    
    local public_ips
    public_ips=$(az network public-ip list --resource-group "$AZURE_RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
    
    if [ -n "$public_ips" ]; then
        while IFS= read -r ip_name; do
            if [ -n "$ip_name" ]; then
                print_status "info" "Deleting public IP: $ip_name"
                az network public-ip delete --resource-group "$AZURE_RESOURCE_GROUP" --name "$ip_name" --no-wait
            fi
        done <<< "$public_ips"
        
        print_status "info" "Waiting for public IP deletions to complete..."
        sleep 10
        print_status "success" "Public IP addresses deleted"
    else
        print_status "info" "No public IP addresses found to delete"
    fi
}

# Function to delete network security group
delete_network_security_group() {
    print_status "info" "Deleting network security group..."
    
    if az network nsg show --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_NSG_NAME" &> /dev/null; then
        print_status "info" "Deleting NSG: $AZURE_NSG_NAME"
        az network nsg delete --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_NSG_NAME"
        print_status "success" "Network security group deleted"
    else
        print_status "info" "Network security group not found"
    fi
}

# Function to delete virtual network
delete_virtual_network() {
    print_status "info" "Deleting virtual network..."
    
    if az network vnet show --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_VNET_NAME" &> /dev/null; then
        print_status "info" "Deleting VNet: $AZURE_VNET_NAME"
        az network vnet delete --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_VNET_NAME"
        print_status "success" "Virtual network deleted"
    else
        print_status "info" "Virtual network not found"
    fi
}

# Function to delete SSH key
delete_ssh_key() {
    print_status "info" "Deleting SSH key..."
    
    if az sshkey show --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_KEY_NAME" &> /dev/null; then
        print_status "info" "Deleting SSH key: $AZURE_KEY_NAME"
        az sshkey delete --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_KEY_NAME" --yes
        print_status "success" "SSH key deleted"
    else
        print_status "info" "SSH key not found"
    fi
}

# Function to delete resource group
delete_resource_group() {
    if [ "$DELETE_RG" -eq 1 ]; then
        print_status "info" "Deleting resource group..."
        print_status "warning" "This will delete ALL resources in the resource group: $AZURE_RESOURCE_GROUP"
        
        az group delete --name "$AZURE_RESOURCE_GROUP" --yes --no-wait
        print_status "success" "Resource group deletion initiated"
        print_status "info" "Resource group deletion is running in the background"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    print_status "info" "Cleaning up local files..."
    
    # Remove inventory file if it exists and was generated for Azure
    if [ -f "inventory.ini" ]; then
        if grep -q "# Deployment type: azure" inventory.ini 2>/dev/null; then
            rm -f inventory.ini
            print_status "success" "Removed Azure inventory file"
        else
            print_status "info" "Keeping existing inventory file (not Azure-generated)"
        fi
    fi
    
    # Clean up any temporary cloud-init files
    rm -f /tmp/cloud-init-*.yml 2>/dev/null || true
    
    print_status "success" "Local cleanup completed"
}

# Function to show final status
show_final_status() {
    echo
    print_status "success" "Azure cleanup completed!"
    echo
    
    if [ "$DELETE_RG" -eq 1 ]; then
        print_status "info" "Resource group deletion is running in the background"
        print_status "info" "You can check the status with:"
        echo "  az group show --name $AZURE_RESOURCE_GROUP"
    else
        print_status "info" "Resource group '$AZURE_RESOURCE_GROUP' was preserved"
        print_status "info" "To delete it completely, run:"
        echo "  $0 --delete-rg"
    fi
    
    echo
    print_status "info" "All lab VMs and associated resources have been removed"
    print_status "success" "No more Azure charges will be incurred for this lab"
}

# Main execution
main() {
    echo "🧹 Azure Rocky Linux 9 Lab Cleanup"
    echo "=================================="
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Confirm deletion
    confirm_deletion
    
    echo
    print_status "info" "Starting Azure resource cleanup..."
    
    # Delete resources in the correct order
    delete_vms
    delete_network_interfaces
    delete_public_ips
    delete_network_security_group
    delete_virtual_network
    delete_ssh_key
    
    # Delete resource group if requested
    delete_resource_group
    
    # Clean up local files
    cleanup_local_files
    
    # Show final status
    show_final_status
}

# Run main function
main "$@" 