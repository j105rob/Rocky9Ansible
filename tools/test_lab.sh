#!/bin/bash

echo "🧪 Testing Rocky Linux 9 Ansible Lab Environment"
echo "================================================"

# Determine the correct path to inventory.ini
# If running from project root, use inventory.ini
# If running from tools directory, use ../inventory.ini
if [ -f "inventory.ini" ]; then
    INVENTORY_PATH="inventory.ini"
elif [ -f "../inventory.ini" ]; then
    INVENTORY_PATH="../inventory.ini"
else
    echo "❌ inventory.ini not found. Please run tools/create_vms_cloudinit.sh first"
    exit 1
fi

echo "✅ Inventory file found"

# Test Ansible connectivity
echo "🔗 Testing Ansible connectivity..."
if ansible all -i "$INVENTORY_PATH" -m ping &>/dev/null; then
    echo "✅ All VMs responding to Ansible ping"
else
    echo "❌ Ansible connectivity failed"
    exit 1
fi

# Test passwordless sudo
echo "🔐 Testing passwordless sudo..."
if ansible all -i "$INVENTORY_PATH" -m shell -a "sudo whoami" --become &>/dev/null; then
    echo "✅ Passwordless sudo working on all VMs"
else
    echo "❌ Passwordless sudo failed"
    exit 1
fi

# Get VM information
echo ""
echo "📊 VM Information:"
ansible all -i "$INVENTORY_PATH" -m setup -a "filter=ansible_hostname,ansible_default_ipv4" | grep -E "(SUCCESS|ansible_hostname|address)" | sed 's/^/  /'

echo ""
echo "🎉 Lab environment is fully functional!"
echo "💡 You can now run Ansible playbooks with: ansible-playbook -i inventory.ini your-playbook.yml" 