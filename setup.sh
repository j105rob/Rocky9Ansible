#!/bin/bash

# Rocky Linux 9 Ansible Lab Setup Wrapper
# This script provides easy access to the main setup tools

set -e

show_help() {
    echo "Rocky Linux 9 Ansible Lab Environment Setup"
    echo "==========================================="
    echo
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo
    echo "Local KVM Commands:"
    echo "  build         Build the base cloud image for KVM"
    echo "  create        Create VMs locally with KVM"
    echo "  clean         Remove existing KVM VMs and recreate"
    echo
    echo "AWS Commands:"
    echo "  aws-create    Create EC2 instances in AWS"
    echo "  aws-clean     Terminate existing AWS instances and recreate"
    echo "  aws-destroy   Terminate all AWS instances (cleanup)"
    echo "  aws-cleanup   Comprehensive AWS cleanup (removes ALL resources)"
    echo
    echo "Azure Commands:"
    echo "  azure-create  Create VMs in Azure"
    echo "  azure-clean   Delete existing Azure VMs and recreate"
    echo "  azure-destroy Delete all Azure VMs (cleanup)"
    echo "  azure-cleanup Comprehensive Azure cleanup (removes ALL resources)"
    echo
    echo "General Commands:"
    echo "  test          Test the lab environment (works with KVM, AWS, and Azure)"
    echo "  help          Show this help message"
    echo
    echo "Examples:"
    echo "  # Local KVM deployment:"
    echo "  $0 build && $0 create"
    echo
    echo "  # AWS deployment:"
    echo "  $0 aws-create"
    echo
    echo "  # Azure deployment:"
    echo "  $0 azure-create"
    echo
    echo "  # Test environment (works with all platforms):"
    echo "  $0 test"
    echo
    echo "  # Cleanup cloud resources:"
    echo "  $0 aws-cleanup    # or azure-cleanup"
    echo
    echo "Environment Variables (or set in config/lab.conf):"
    echo "  AWS_REGION        AWS region (default: us-east-1)"
    echo "  AWS_INSTANCE_TYPE EC2 instance type (default: t3.medium)"
    echo "  AZURE_LOCATION    Azure region (default: eastus)"
    echo "  AZURE_VM_SIZE     Azure VM size (default: Standard_B2s)"
}

case "${1:-help}" in
    build)
        echo "🔨 Building Rocky Linux 9 base cloud image for KVM..."
        sudo tools/build_rocky9_image.sh "${@:2}"
        ;;
    create)
        echo "🚀 Creating VMs locally with KVM..."
        sudo tools/create_vms_cloudinit.sh "${@:2}"
        ;;
    clean)
        echo "🧹 Cleaning and recreating KVM VMs..."
        sudo tools/create_vms_cloudinit.sh --clean "${@:2}"
        ;;
    aws-create)
        echo "☁️ Creating EC2 instances in AWS..."
        tools/create_vms_aws.sh "${@:2}"
        ;;
    aws-clean)
        echo "☁️ Cleaning and recreating AWS instances..."
        tools/create_vms_aws.sh --clean "${@:2}"
        ;;
    aws-destroy)
        echo "💥 Terminating all AWS instances..."
        tools/create_vms_aws.sh --clean
        echo "✅ All AWS instances terminated"
        ;;
    aws-cleanup)
        echo "🧹 Comprehensive AWS cleanup (removes ALL resources)..."
        tools/cleanup_aws.sh
        ;;
    azure-create)
        echo "☁️ Creating VMs in Azure..."
        tools/create_vms_azure.sh "${@:2}"
        ;;
    azure-clean)
        echo "☁️ Cleaning and recreating Azure VMs..."
        tools/create_vms_azure.sh --clean "${@:2}"
        ;;
    azure-destroy)
        echo "💥 Deleting all Azure VMs..."
        tools/create_vms_azure.sh --clean
        echo "✅ All Azure VMs deleted"
        ;;
    azure-cleanup)
        echo "🧹 Comprehensive Azure cleanup (removes ALL resources)..."
        tools/cleanup_azure.sh
        ;;
    test)
        echo "🧪 Testing lab environment..."
        tools/test_lab.sh "${@:2}"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo
        show_help
        exit 1
        ;;
esac 