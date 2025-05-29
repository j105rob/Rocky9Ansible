# AWS Integration Guide

This guide explains how to use the AWS integration features of the Rocky Linux 9 Ansible Lab Environment.

## Overview

The project now supports both local KVM deployment and AWS EC2 deployment, giving you flexibility to choose the best option for your needs.

## Quick Start with AWS

### 1. Prerequisites

```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure AWS credentials
aws configure
```

### 2. Deploy to AWS

```bash
# Single command deployment
./setup.sh aws-create

# Test the environment
./setup.sh test

# Run example playbook
ansible-playbook -i inventory.ini examples/basic-setup.yml
```

### 3. Cleanup (Important!)

```bash
# Quick cleanup (instances only)
./setup.sh aws-destroy

# Complete cleanup (all resources)
./setup.sh aws-cleanup
```

## AWS Resources Created

The AWS deployment automatically creates:

### Networking
- **VPC**: `ansible-lab-vpc` (10.0.0.0/16)
- **Subnet**: Public subnet (10.0.1.0/24)
- **Internet Gateway**: For internet access
- **Route Table**: Routes traffic to internet gateway
- **Security Group**: `ansible-lab-sg` with SSH access

### Compute
- **3 EC2 Instances**: controller, worker1, worker2
- **Instance Type**: t3.medium (configurable)
- **AMI**: Latest Rocky Linux 9 official image
- **Key Pair**: `ansible-lab-key` (auto-uploaded)

### Configuration
- **Cloud-init**: Automatic setup with passwordless SSH/sudo
- **SSH Keys**: Automatically uploaded and configured
- **Ansible Inventory**: Auto-generated with public IPs

## Configuration Options

### Environment Variables

```bash
# AWS Region (default: us-east-1)
export AWS_REGION=us-west-2

# Instance Type (default: t3.medium)
export INSTANCE_TYPE=t3.large

# Key Pair Name (default: ansible-lab-key)
export KEY_NAME=my-custom-key

# Deploy with custom settings
./setup.sh aws-create
```

### Instance Types and Costs

| Instance Type | vCPUs | Memory | Cost/Hour | Monthly Cost (3 instances) |
|---------------|-------|--------|-----------|----------------------------|
| t3.micro      | 2     | 1 GB   | $0.0104   | ~$22.50                   |
| t3.small      | 2     | 2 GB   | $0.0208   | ~$45.00                   |
| t3.medium     | 2     | 4 GB   | $0.0416   | ~$90.00                   |
| t3.large      | 2     | 8 GB   | $0.0832   | ~$180.00                  |

*Costs are approximate and vary by region*

## AWS vs Local KVM

### When to Use AWS
- ✅ Need internet access from VMs
- ✅ Want to access lab from multiple locations
- ✅ Testing cloud deployment scenarios
- ✅ Demonstrating to remote teams
- ✅ Don't have local virtualization capability

### When to Use Local KVM
- ✅ Want to avoid cloud costs
- ✅ Have sufficient local resources
- ✅ Working offline or with limited internet
- ✅ Learning basic Ansible concepts
- ✅ Long-term lab environment

## Security Considerations

### AWS Security
- Security group allows SSH (port 22) from anywhere (0.0.0.0/0)
- Consider restricting to your IP: `--cidr YOUR_IP/32`
- SSH key authentication only (password auth disabled)
- Root login disabled

### Recommended Security Improvements
```bash
# Get your public IP
MY_IP=$(curl -s ifconfig.me)

# Modify security group to restrict SSH access
aws ec2 authorize-security-group-ingress \
    --group-id sg-xxxxxxxxx \
    --protocol tcp \
    --port 22 \
    --cidr $MY_IP/32

# Remove the open rule
aws ec2 revoke-security-group-ingress \
    --group-id sg-xxxxxxxxx \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0
```

## Troubleshooting

### Common Issues

#### 1. AWS CLI Not Configured
```
Error: AWS credentials not configured
```
**Solution**: Run `aws configure` and enter your credentials

#### 2. Insufficient Permissions
```
Error: User is not authorized to perform: ec2:CreateVpc
```
**Solution**: Ensure your AWS user has EC2 full access permissions

#### 3. Instance Limit Exceeded
```
Error: You have requested more instances than your current instance limit
```
**Solution**: Request a limit increase or use a different region

#### 4. SSH Connection Timeout
```
Error: Connection failed (may need more time for cloud-init)
```
**Solution**: Wait longer for cloud-init to complete, or check security group rules

### Debugging Commands

```bash
# Check AWS credentials
aws sts get-caller-identity

# List running instances
aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,InstanceId:InstanceId,State:State.Name,IP:PublicIpAddress}'

# Check security groups
aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=ansible-lab-sg"

# View cloud-init logs (on instance)
ssh rocky@INSTANCE_IP "sudo tail -f /var/log/cloud-init-output.log"
```

## Cost Management

### Monitoring Costs
- Use AWS Cost Explorer to monitor spending
- Set up billing alerts for unexpected charges
- Tag resources for better cost tracking

### Cost Optimization
```bash
# Use smaller instances for basic testing
export INSTANCE_TYPE=t3.micro
./setup.sh aws-create

# Stop instances when not in use (preserves data)
aws ec2 stop-instances --instance-ids i-1234567890abcdef0

# Start instances when needed
aws ec2 start-instances --instance-ids i-1234567890abcdef0
```

### Cleanup Checklist
- [ ] Terminate all instances: `./setup.sh aws-destroy`
- [ ] Delete VPC and networking: `./setup.sh aws-cleanup`
- [ ] Verify no resources remain in AWS console
- [ ] Check final bill to ensure no ongoing charges

## Advanced Usage

### Custom VPC Configuration
Modify `tools/create_vms_aws.sh` to use existing VPC:
```bash
# Set existing VPC ID
VPC_ID="vpc-existing123"
SUBNET_ID="subnet-existing456"
```

### Multiple Environments
Deploy multiple labs with different names:
```bash
export KEY_NAME=lab1-key
export VPC_NAME=lab1-vpc
./setup.sh aws-create

export KEY_NAME=lab2-key  
export VPC_NAME=lab2-vpc
./setup.sh aws-create
```

### Integration with CI/CD
Use in automated testing pipelines:
```yaml
# GitHub Actions example
- name: Deploy AWS Lab
  run: |
    export AWS_REGION=us-east-1
    export INSTANCE_TYPE=t3.micro
    ./setup.sh aws-create
    
- name: Run Tests
  run: |
    ansible-playbook -i inventory.ini tests/test-playbook.yml
    
- name: Cleanup
  run: |
    ./setup.sh aws-cleanup
```

## Support

For AWS-specific issues:
1. Check the troubleshooting section above
2. Review AWS CloudTrail logs for API errors
3. Verify IAM permissions
4. Check AWS service health dashboard
5. Open an issue in the project repository

Remember: Always clean up AWS resources when done to avoid unexpected charges! 