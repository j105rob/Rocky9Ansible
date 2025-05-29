#!/bin/bash

# Configuration variables
CLOUD_IMAGE_URL="https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
IMAGE_OUTPUT="/media/ubuntu/store/VMs/rocky9-cloud-base.qcow2"
TEMP_DIR="/tmp/rocky9-build"

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Download and customize Rocky Linux 9 cloud image"
    echo
    echo "Options:"
    echo "  --force    Overwrite existing base image"
    echo "  --help     Show this help message"
}

# Process command line arguments
FORCE_BUILD=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_BUILD=1
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

# Check if image already exists
if [ -f "$IMAGE_OUTPUT" ] && [ "$FORCE_BUILD" -eq 0 ]; then
    echo "Base image already exists at $IMAGE_OUTPUT"
    echo "Use --force to overwrite"
    exit 0
fi

# Check if required tools are installed
for tool in wget virt-customize; do
    if ! command -v $tool &> /dev/null; then
        echo "$tool is required but not installed. Installing..."
        apt-get update && apt-get install -y libguestfs-tools wget
        break
    fi
done

# Create temporary directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

echo "Downloading Rocky Linux 9 cloud image..."
wget -O rocky9-cloud-original.qcow2 "$CLOUD_IMAGE_URL"

if [ $? -ne 0 ]; then
    echo "Failed to download cloud image"
    exit 1
fi

echo "Customizing cloud image..."

# Customize the image
virt-customize -a rocky9-cloud-original.qcow2 \
    --install cloud-init,cloud-utils-growpart,qemu-guest-agent,vim,wget,curl,git,htop \
    --run-command 'systemctl enable cloud-init cloud-init-local cloud-config cloud-final sshd qemu-guest-agent' \
    --run-command 'yum clean all' \
    --run-command 'rm -rf /var/cache/yum /tmp/* /var/tmp/*' \
    --run-command 'history -c' \
    --selinux-relabel

if [ $? -ne 0 ]; then
    echo "Failed to customize cloud image"
    exit 1
fi

echo "Optimizing image..."
virt-sparsify --compress rocky9-cloud-original.qcow2 "$IMAGE_OUTPUT"

# Set proper ownership
chown libvirt-qemu:libvirt-qemu "$IMAGE_OUTPUT"
chmod 644 "$IMAGE_OUTPUT"

# Clean up temporary files
rm -rf "$TEMP_DIR"

echo "Cloud-init-ready Rocky 9 base image created successfully at: $IMAGE_OUTPUT"
echo "Image size: $(du -h "$IMAGE_OUTPUT" | cut -f1)" 