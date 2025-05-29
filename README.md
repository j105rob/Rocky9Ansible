# Rocky Linux 9 Ansible Lab Environment

This project sets up a KVM-based lab environment with Rocky Linux 9 VMs for Ansible practice and testing. The setup uses cloud-init for fast VM deployment and configuration.

## Architecture

- **Host**: Ubuntu with KVM/libvirt
- **VMs**: 3 Rocky Linux 9 instances (controller, worker1, worker2)
- **Network**: Default libvirt NAT network (192.168.122.0/24)
- **Storage**: `/media/ubuntu/store/VMs`
- **Deployment**: Cloud-init based for rapid provisioning

## VM Specifications

Each VM is configured with:
- **vCPUs**: 2
- **Memory**: 4GB
- **Storage**: 20GB (thin provisioned)
- **OS**: Rocky Linux 9 (cloud-init ready)
- **User**: rocky (sudo access)
- **Network**: DHCP on default libvirt network

## Prerequisites

### System Requirements
- Ubuntu host with KVM support
- At least 16GB RAM (for 3 VMs + host)
- 100GB free storage space
- Rocky Linux 9 ISO file

### Required Packages
```bash
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils \
    virt-manager virtinst virt-viewer genisoimage libguestfs-tools
```

### Ansible Requirements
```bash
sudo apt install -y ansible
ansible-galaxy collection install community.libvirt
```

## Quick Start

### Option 1: Using the Setup Wrapper (Recommended)

```bash
# Build base image and create VMs in one command
./setup.sh build && ./setup.sh create

# Or step by step:
./setup.sh build     # Build the base cloud image
./setup.sh create    # Create VMs with full automation
./setup.sh test      # Verify everything works
```

### Option 2: Using Tools Directly

1. **Build the base cloud image:**
   ```bash
   sudo tools/build_rocky9_image.sh
   ```

2. **Create VMs with full automation:**
   ```bash
   sudo tools/create_vms_cloudinit.sh
   ```

3. **Test Ansible connectivity:**
   ```bash
   ansible all -i inventory.ini -m ping
   ```

4. **Verify everything works:**
   ```bash
   tools/test_lab.sh
   ```

### What This Does Automatically:
- Generate SSH key pair if not present
- Create 3 VMs with passwordless SSH and sudo
- Generate Ansible inventory file
- Test connectivity to ensure everything works

## Project Structure

```
Rocky9Ansible/
├── setup.sh                       # Main setup wrapper script
├── tools/
│   ├── build_rocky9_image.sh       # Build cloud-init base image
│   ├── create_vms_cloudinit.sh     # Standalone VM creation script
│   ├── create_vms.sh               # Legacy ISO-based script
│   └── test_lab.sh                 # Lab environment verification
├── inventory.ini                   # Auto-generated Ansible inventory
├── rocky9.ks                       # Kickstart for legacy method
├── site.yml                        # Main Ansible playbook
├── group_vars/
│   └── all.yml                     # VM configuration variables
├── inventory/
│   └── hosts                       # Ansible inventory
└── roles/
    ├── kvm_host/                   # KVM host setup role
    │   └── tasks/main.yml
    └── rocky9_vm/                  # VM creation role
        ├── tasks/
        │   ├── main.yml            # Main VM creation tasks
        │   └── cloud_init.yml      # Cloud-init setup tasks
        └── templates/
            ├── user-data.j2        # Cloud-init user data
            └── meta-data.j2        # Cloud-init metadata
```

## Configuration

### VM Configuration
Edit `group_vars/all.yml` to customize:
- VM specifications (CPU, memory, disk)
- Storage locations
- User credentials
- Network settings

### User Credentials
Default credentials for VMs:
- **Username**: rocky
- **Password**: rocky123
- **SSH**: Key-based authentication (if SSH key exists)

## Network Access

VMs use the default libvirt NAT network:
- **Network**: 192.168.122.0/24
- **Gateway**: 192.168.122.1
- **DHCP**: Automatic IP assignment

To find VM IP addresses:
```bash
# List all VMs and their IPs
virsh net-dhcp-leases default

# Connect to a specific VM
ssh rocky@<vm-ip>
```

## Management Commands

### VM Operations
```bash
# List VMs
virsh list --all

# Start/stop VMs
virsh start controller
virsh shutdown controller

# Connect to VM console
virsh console controller

# Remove VMs
virsh destroy controller
virsh undefine controller --nvram
```

### Storage Management
```bash
# List VM disks
ls -la /media/ubuntu/store/VMs/

# Check disk usage
qemu-img info /media/ubuntu/store/VMs/controller.qcow2
```

## Troubleshooting

### Common Issues

1. **Permission Denied on Storage**
   ```bash
   sudo chown -R libvirt-qemu:libvirt-qemu /media/ubuntu/store/VMs/
   sudo chmod 755 /media/ubuntu/store/
   ```

2. **Network Not Available**
   ```bash
   sudo virsh net-start default
   sudo virsh net-autostart default
   ```

3. **Cloud-init Not Working**
   - Check cloud-init logs: `sudo tail -f /var/log/cloud-init.log`
   - Verify cloud-init ISO is attached to VM
   - Ensure base image has cloud-init installed

4. **Build Script Fails**
   - Verify Rocky Linux ISO path is correct
   - Check available disk space
   - Ensure virtualization is enabled in BIOS

### Log Locations
- **Cloud-init logs**: `/var/log/cloud-init*.log`
- **Libvirt logs**: `/var/log/libvirt/qemu/`
- **System logs**: `journalctl -u libvirtd`

## Advanced Usage

### Custom Base Image
To rebuild the base image with different packages:
1. Edit the kickstart section in `tools/build_rocky9_image.sh`
2. Run: `sudo tools/build_rocky9_image.sh --force`

### Network Customization
To use a custom network instead of default:
1. Create custom libvirt network
2. Update `rocky9_vm_template.network` in `group_vars/all.yml`

### SSH Key Setup
To use SSH key authentication:
1. Generate SSH key: `ssh-keygen -t rsa -b 4096`
2. The script will automatically include `~/.ssh/id_rsa.pub` if it exists

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with a clean environment
5. Submit a pull request

## License

This project is licensed under the MIT License.

## Features

- **Modern Cloud-Init Approach**: Fast VM deployment using official Rocky Linux cloud images
- **Automated SSH Key Management**: Automatically generates SSH keys for passwordless authentication
- **Passwordless Access**: Both SSH and sudo configured for seamless automation
- **Ansible Ready**: Auto-generated inventory file with proper configuration
- **Quick Deployment**: ~30 seconds total deployment time for all 3 VMs
- **Connectivity Testing**: Automatic verification that SSH and sudo work correctly
- **Easy Cleanup**: Simple `--clean` flag to remove and recreate VMs
- **Production-Like Environment**: Uses standard cloud deployment practices