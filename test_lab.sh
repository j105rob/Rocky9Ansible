#!/bin/bash

echo "🧪 Testing Rocky Linux 9 Ansible Lab Environment"
echo "================================================"

# Check if inventory file exists
if [ ! -f "inventory.ini" ]; then
    echo "❌ inventory.ini not found. Please run ./create_vms_cloudinit.sh first"
    exit 1
fi

echo "✅ Inventory file found"

# Test Ansible connectivity
echo "🔗 Testing Ansible connectivity..."
if ansible all -i inventory.ini -m ping &>/dev/null; then
    echo "✅ All VMs responding to Ansible ping"
else
    echo "❌ Ansible connectivity failed"
    exit 1
fi

# Test passwordless sudo
echo "🔐 Testing passwordless sudo..."
if ansible all -i inventory.ini -m shell -a "sudo whoami" --become &>/dev/null; then
    echo "✅ Passwordless sudo working on all VMs"
else
    echo "❌ Passwordless sudo failed"
    exit 1
fi

# Get VM information
echo ""
echo "📊 VM Information:"
ansible all -i inventory.ini -m setup -a "filter=ansible_hostname,ansible_default_ipv4" | grep -E "(SUCCESS|ansible_hostname|address)" | sed 's/^/  /'

echo ""
echo "🎉 Lab environment is fully functional!"
echo "💡 You can now run Ansible playbooks with: ansible-playbook -i inventory.ini your-playbook.yml" 