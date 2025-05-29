#!/bin/bash

# AWS Cleanup Script for Rocky Linux 9 Ansible Lab
# This script removes all AWS resources created by the lab

AWS_REGION="${AWS_REGION:-us-east-1}"
KEY_NAME="${KEY_NAME:-ansible-lab-key}"
SECURITY_GROUP_NAME="ansible-lab-sg"
VPC_NAME="ansible-lab-vpc"

echo "🧹 AWS Cleanup for Rocky Linux 9 Ansible Lab"
echo "============================================="
echo "Region: $AWS_REGION"
echo

# Function to terminate instances
cleanup_instances() {
    echo "🔍 Looking for lab instances..."
    
    INSTANCE_IDS=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=controller,worker1,worker2" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
        echo "🗑️ Terminating instances: $INSTANCE_IDS"
        aws ec2 terminate-instances \
            --instance-ids $INSTANCE_IDS \
            --region "$AWS_REGION"
        
        echo "⏳ Waiting for instances to terminate..."
        aws ec2 wait instance-terminated \
            --instance-ids $INSTANCE_IDS \
            --region "$AWS_REGION"
        echo "✅ Instances terminated"
    else
        echo "ℹ️ No lab instances found"
    fi
}

# Function to delete security group
cleanup_security_group() {
    echo "🔍 Looking for security group..."
    
    # Get VPC ID first
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$VPC_NAME" \
        --query 'Vpcs[0].VpcId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
        SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" "Name=vpc-id,Values=$VPC_ID" \
            --query 'SecurityGroups[0].GroupId' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null)
        
        if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
            echo "🗑️ Deleting security group: $SG_ID"
            aws ec2 delete-security-group \
                --group-id "$SG_ID" \
                --region "$AWS_REGION"
            echo "✅ Security group deleted"
        else
            echo "ℹ️ Security group not found"
        fi
    fi
}

# Function to delete VPC and associated resources
cleanup_vpc() {
    echo "🔍 Looking for VPC..."
    
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$VPC_NAME" \
        --query 'Vpcs[0].VpcId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
        echo "🗑️ Cleaning up VPC: $VPC_ID"
        
        # Delete subnets
        SUBNET_IDS=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            --query 'Subnets[].SubnetId' \
            --output text \
            --region "$AWS_REGION")
        
        for subnet_id in $SUBNET_IDS; do
            if [ "$subnet_id" != "None" ]; then
                echo "  🗑️ Deleting subnet: $subnet_id"
                aws ec2 delete-subnet \
                    --subnet-id "$subnet_id" \
                    --region "$AWS_REGION"
            fi
        done
        
        # Delete route tables (except main)
        ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
            --output text \
            --region "$AWS_REGION")
        
        for rt_id in $ROUTE_TABLE_IDS; do
            if [ "$rt_id" != "None" ]; then
                echo "  🗑️ Deleting route table: $rt_id"
                aws ec2 delete-route-table \
                    --route-table-id "$rt_id" \
                    --region "$AWS_REGION"
            fi
        done
        
        # Detach and delete internet gateway
        IGW_ID=$(aws ec2 describe-internet-gateways \
            --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
            --query 'InternetGateways[0].InternetGatewayId' \
            --output text \
            --region "$AWS_REGION")
        
        if [ "$IGW_ID" != "None" ] && [ -n "$IGW_ID" ]; then
            echo "  🗑️ Detaching internet gateway: $IGW_ID"
            aws ec2 detach-internet-gateway \
                --internet-gateway-id "$IGW_ID" \
                --vpc-id "$VPC_ID" \
                --region "$AWS_REGION"
            
            echo "  🗑️ Deleting internet gateway: $IGW_ID"
            aws ec2 delete-internet-gateway \
                --internet-gateway-id "$IGW_ID" \
                --region "$AWS_REGION"
        fi
        
        # Delete VPC
        echo "  🗑️ Deleting VPC: $VPC_ID"
        aws ec2 delete-vpc \
            --vpc-id "$VPC_ID" \
            --region "$AWS_REGION"
        
        echo "✅ VPC and associated resources deleted"
    else
        echo "ℹ️ VPC not found"
    fi
}

# Function to delete key pair
cleanup_key_pair() {
    echo "🔍 Looking for key pair..."
    
    if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &> /dev/null; then
        echo "🗑️ Deleting key pair: $KEY_NAME"
        aws ec2 delete-key-pair \
            --key-name "$KEY_NAME" \
            --region "$AWS_REGION"
        echo "✅ Key pair deleted"
    else
        echo "ℹ️ Key pair not found"
    fi
}

# Main cleanup process
echo "⚠️ This will delete ALL AWS resources created by the Ansible lab!"
echo "This includes:"
echo "  - EC2 instances (controller, worker1, worker2)"
echo "  - VPC and networking components"
echo "  - Security groups"
echo "  - SSH key pair"
echo

read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" = "yes" ]; then
    echo
    echo "🚀 Starting cleanup process..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        echo "❌ AWS CLI not found"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ AWS credentials not configured"
        exit 1
    fi
    
    # Cleanup in order
    cleanup_instances
    cleanup_security_group
    cleanup_vpc
    cleanup_key_pair
    
    echo
    echo "🎉 Cleanup completed!"
    echo "💰 All AWS resources have been removed to prevent charges"
    
    # Remove local inventory file if it exists
    if [ -f "../inventory.ini" ]; then
        echo "🗑️ Removing local inventory file"
        rm -f "../inventory.ini"
    fi
    
else
    echo "❌ Cleanup cancelled"
    exit 1
fi 