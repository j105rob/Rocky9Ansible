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
    echo "Commands:"
    echo "  build     Build the base cloud image"
    echo "  create    Create VMs with full automation"
    echo "  test      Test the lab environment"
    echo "  clean     Remove existing VMs and recreate"
    echo "  help      Show this help message"
    echo
    echo "Examples:"
    echo "  $0 build                    # Build base image"
    echo "  $0 create                   # Create VMs"
    echo "  $0 clean                    # Clean and recreate VMs"
    echo "  $0 test                     # Test environment"
    echo
    echo "For full automation (recommended):"
    echo "  $0 build && $0 create"
}

case "${1:-help}" in
    build)
        echo "🔨 Building Rocky Linux 9 base cloud image..."
        sudo tools/build_rocky9_image.sh "${@:2}"
        ;;
    create)
        echo "🚀 Creating VMs with full automation..."
        sudo tools/create_vms_cloudinit.sh "${@:2}"
        ;;
    clean)
        echo "🧹 Cleaning and recreating VMs..."
        sudo tools/create_vms_cloudinit.sh --clean "${@:2}"
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