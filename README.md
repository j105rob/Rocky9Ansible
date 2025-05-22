# Rocky 9 KVM Ansible Project

This Ansible project automates the creation and management of Rocky Linux 9 virtual machines using KVM on Ubuntu hosts.

## Prerequisites

- Ubuntu host with KVM installed
- Ansible 2.9 or higher
- Sufficient storage space for VM images
- libvirt and associated tools

## Setup

1. Install required dependencies on Ubuntu host:
```bash
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst
```

2. Install Ansible requirements:
```bash
ansible-galaxy collection install community.libvirt
```

3. Configure variables in `group_vars/all.yml` to match your environment

## Usage

1. Update inventory file with your target hosts
2. Run the playbook:
```bash
ansible-playbook -i inventory site.yml
```

## Project Structure

```
.
├── group_vars/
│   └── all.yml
├── inventory/
│   └── hosts
├── roles/
│   ├── kvm_host/
│   └── rocky9_vm/
├── site.yml
└── README.md
```