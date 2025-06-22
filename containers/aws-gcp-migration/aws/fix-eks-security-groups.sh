#!/bin/bash

# Quick Fix for EKS Security Group Issues
# This script fixes common security group problems that prevent nodes from joining

set -e

REGION="ap-southeast-2"
CLUSTER_NAME="cymbalbank-cluster"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo -e "${BLUE}=== Fixing EKS Security Groups ===${NC}"
echo ""

# Get cluster security group
print_status "Getting cluster security group..."
CLUSTER_SG=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

if [ "$CLUSTER_SG" == "None" ] || [ -z "$CLUSTER_SG" ]; then
    print_error "Could not find cluster security group"
    exit 1
fi

print_success "Cluster Security Group: $CLUSTER_SG"

# Get VPC ID
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)
print_success "VPC ID: $VPC_ID"

# Find node security groups
print_status "Finding node security groups..."
NODE_SGS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=*node*" \
    --region $REGION \
    --query 'SecurityGroups[].GroupId' \
    --output text)

if [ -n "$NODE_SGS" ]; then
    for NODE_SG in $NODE_SGS; do
        print_status "Processing node security group: $NODE_SG"
        
        # Add rule: Nodes can communicate with cluster
        aws ec2 authorize-security-group-ingress \
            --group-id $NODE_SG \
            --protocol tcp \
            --port 443 \
            --source-group $CLUSTER_SG \
            --region $REGION 2>/dev/null && print_success "Added node->cluster rule" || print_warning "Rule might already exist"
        
        # Add rule: Nodes can communicate with each other
        aws ec2 authorize-security-group-ingress \
            --group-id $NODE_SG \
            --protocol all \
            --source-group $NODE_SG \
            --region $REGION 2>/dev/null && print_success "Added node->node rule" || print_warning "Rule might already exist"
        
        # Add rule: Cluster can communicate with nodes
        aws ec2 authorize-security-group-ingress \
            --group-id $CLUSTER_SG \
            --protocol tcp \
            --port 443 \
            --source-group $NODE_SG \
            --region $REGION 2>/dev/null && print_success "Added cluster->node rule" || print_warning "Rule might already exist"
    done
else
    print_warning "No node security groups found"
fi

# Check subnet tags
print_status "Checking subnet tags..."
SUBNET_IDS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.subnetIds' --output text)

for subnet in $SUBNET_IDS; do
    print_status "Checking subnet: $subnet"
    
    # Check if subnet has required tags
    HAS_ELB_TAG=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$subnet" "Name=key,Values=kubernetes.io/role/elb" --region $REGION --query 'Tags[0].Value' --output text)
    HAS_INTERNAL_TAG=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$subnet" "Name=key,Values=kubernetes.io/role/internal-elb" --region $REGION --query 'Tags[0].Value' --output text)
    
    if [ "$HAS_ELB_TAG" == "None" ] || [ -z "$HAS_ELB_TAG" ]; then
        print_warning "Subnet $subnet missing kubernetes.io/role/elb tag"
    fi
    
    if [ "$HAS_INTERNAL_TAG" == "None" ] || [ -z "$HAS_INTERNAL_TAG" ]; then
        print_warning "Subnet $subnet missing kubernetes.io/role/internal-elb tag"
    fi
done

print_success "Security group fixes applied!"
echo ""
print_warning "Next steps:"
echo "1. Wait 5-10 minutes for changes to take effect"
echo "2. Check node group status: eksctl get nodegroup --cluster=$CLUSTER_NAME --region=$REGION"
echo "3. If still failing, try deleting and recreating the node group" 