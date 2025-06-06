# Azure Integration and Code Organization Improvements

## Overview

This document outlines the Azure integration added to the Rocky Linux 9 Ansible Lab Environment and the code organization improvements made to support multiple cloud platforms.

## Code Organization Improvements

### 1. Centralized Configuration Management

**New File**: `config/lab.conf.example`
- Added Azure configuration options
- Standardized environment variable names
- Added network configuration settings
- Supports all three deployment types: KVM, AWS, and Azure

**Key Improvements**:
- Consistent naming conventions (e.g., `AWS_INSTANCE_TYPE` instead of `INSTANCE_TYPE`)
- Platform-specific prefixes for clarity
- Shared network configuration

### 2. Common Functions Library

**New File**: `tools/common.sh`
- Centralized configuration loading
- Shared SSH key management
- Common cloud-init generation
- Unified inventory generation
- Standardized status reporting
- Cost information display

**Benefits**:
- Eliminates code duplication across scripts
- Consistent behavior across all platforms
- Easier maintenance and updates
- Standardized error handling and logging

### 3. Enhanced Setup Script

**Updated**: `setup.sh`
- Added Azure commands (`azure-create`, `azure-clean`, `azure-destroy`, `azure-cleanup`)
- Updated help documentation
- Consistent command structure across all platforms

## Azure Integration Features

### 1. Azure VM Creation Script

**New File**: `tools/create_vms_azure.sh`

**Features**:
- Creates Azure Resource Group automatically
- Sets up Virtual Network and Subnet
- Configures Network Security Group with SSH access
- Uploads SSH keys to Azure
- Creates 3 VMs (controller, worker1, worker2) using RHEL 9
- Uses cloud-init for automated configuration
- Generates Ansible inventory automatically
- Tests connectivity before completion

**VM Specifications**:
- **Default VM Size**: Standard_B2s (2 vCPUs, 4GB RAM)
- **OS**: RHEL 9 (compatible with Rocky Linux)
- **Network**: 10.0.0.0/16 VNet with 10.0.1.0/24 subnet
- **Security**: NSG with SSH (port 22) access
- **Authentication**: SSH key-based with passwordless sudo

### 2. Azure Cleanup Script

**New File**: `tools/cleanup_azure.sh`

**Features**:
- Comprehensive resource cleanup
- Deletes VMs, NICs, Public IPs, NSG, VNet, and SSH keys
- Optional resource group deletion
- Confirmation prompts (can be bypassed with `--force`)
- Cleans up local inventory files
- Cost-aware messaging

### 3. Cost Management

**Azure Cost Information**:
- **Standard_B2s**: ~$0.04/hour per VM
- **Total for 3 VMs**: ~$0.12/hour
- **Daily cost**: ~$2.88/day
- **Monthly cost**: ~$86/month

**Cost Controls**:
- Clear cost warnings during deployment
- Automatic cleanup commands
- Resource group isolation for easy bulk deletion

## Platform Comparison

| Feature | Local KVM | AWS | Azure |
|---------|-----------|-----|-------|
| **Cost** | Free | ~$0.125/hour | ~$0.12/hour |
| **Setup Time** | ~2 minutes | ~3-4 minutes | ~3-4 minutes |
| **OS Image** | Custom Rocky 9 | Rocky 9 marketplace | RHEL 9 (compatible) |
| **Network** | libvirt NAT | VPC with IGW | VNet with NSG |
| **Authentication** | SSH keys | SSH keys | SSH keys |
| **Cleanup** | Manual VM removal | Comprehensive AWS cleanup | Comprehensive Azure cleanup |

## Usage Examples

### Quick Start with Azure

```bash
# Prerequisites
az login

# Deploy lab environment
./setup.sh azure-create

# Test connectivity
./setup.sh test

# Run example playbook
ansible-playbook -i inventory.ini examples/basic-setup.yml

# Cleanup when done
./setup.sh azure-cleanup
```

### Configuration Customization

```bash
# Copy and edit configuration
cp config/lab.conf.example config/lab.conf

# Edit settings
vim config/lab.conf

# Deploy with custom settings
./setup.sh azure-create
```

### Environment Variables

```bash
# Set Azure region
export AZURE_LOCATION=westus2

# Set VM size
export AZURE_VM_SIZE=Standard_B4ms

# Deploy
./setup.sh azure-create
```

## Technical Implementation Details

### Cloud-Init Configuration

The Azure integration uses cloud-init for VM configuration:

```yaml
#cloud-config
users:
  - name: rocky
    groups: [wheel, adm, systemd-journal]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - [SSH_PUBLIC_KEY]

packages:
  - vim, git, htop, tree, curl, wget, python3, python3-pip

runcmd:
  - systemctl enable sshd
  - systemctl start sshd
  - usermod -aG wheel rocky
```

### Network Architecture

**Azure Network Setup**:
- **Resource Group**: `ansible-lab-rg`
- **Virtual Network**: `ansible-lab-vnet` (10.0.0.0/16)
- **Subnet**: `ansible-lab-subnet` (10.0.1.0/24)
- **NSG**: `ansible-lab-nsg` with SSH rule
- **Public IPs**: Standard SKU for each VM

### Error Handling

All scripts include comprehensive error handling:
- Prerequisites checking (CLI tools, authentication)
- Resource existence validation
- Timeout handling for VM creation
- Connectivity testing with retries
- Graceful cleanup on failures

## Security Considerations

### SSH Key Management
- Automatic SSH key generation if not present
- Keys stored in `/home/ubuntu/.ssh/`
- Public keys uploaded to cloud platforms
- Private keys remain local

### Network Security
- **Azure**: NSG rules limit access to SSH (port 22)
- **AWS**: Security groups with SSH access
- **KVM**: NAT network isolation

### Access Control
- Passwordless sudo for automation
- SSH key-based authentication
- No password authentication by default (configurable)

## Maintenance and Updates

### Adding New Cloud Platforms

To add support for additional cloud platforms:

1. Create `tools/create_vms_[platform].sh`
2. Create `tools/cleanup_[platform].sh`
3. Add configuration options to `config/lab.conf.example`
4. Update `setup.sh` with new commands
5. Add platform-specific functions to `tools/common.sh`
6. Update documentation

### Configuration Management

The centralized configuration system makes it easy to:
- Add new configuration options
- Maintain consistency across platforms
- Support environment variable overrides
- Provide sensible defaults

## Future Enhancements

### Potential Improvements

1. **Terraform Integration**: Use Terraform for infrastructure as code
2. **Ansible Roles**: Create Ansible roles for cloud infrastructure
3. **Multi-Region Support**: Deploy across multiple regions
4. **Auto-scaling**: Support for variable VM counts
5. **Monitoring**: Integration with cloud monitoring services
6. **Backup**: Automated VM snapshot/backup capabilities

### Platform-Specific Enhancements

**Azure**:
- Azure Key Vault integration for secrets management
- Azure Monitor integration
- Support for Azure Spot instances for cost savings
- Integration with Azure DevOps

**AWS**:
- CloudFormation template support
- AWS Systems Manager integration
- Support for EC2 Spot instances
- CloudWatch monitoring integration

**KVM**:
- Libvirt network customization
- Storage pool management
- VM template versioning
- Snapshot management

## Conclusion

The Azure integration and code organization improvements provide:

1. **Consistent Experience**: Unified interface across all platforms
2. **Cost Efficiency**: Clear cost information and easy cleanup
3. **Maintainability**: Shared code reduces duplication
4. **Scalability**: Easy to add new platforms and features
5. **Production-Ready**: Follows cloud best practices

The lab environment now supports three deployment options with consistent tooling, making it suitable for various learning and testing scenarios. 