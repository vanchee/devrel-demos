#!/bin/bash

# EKS Node Creation Failure Troubleshooting Script
# This script helps diagnose and fix common EKS node creation issues

set -e

# Configuration
REGION="ap-southeast-2"
CLUSTER_NAME="cymbalbank-cluster"
NODEGROUP_NAME="standard-workers"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo -e "${BLUE}=== EKS Node Creation Failure Troubleshooting ===${NC}"
echo ""

# 1. Check EKS Cluster Status
print_status "1. Checking EKS cluster status..."
CLUSTER_STATUS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    print_success "EKS cluster is ACTIVE"
elif [ "$CLUSTER_STATUS" == "NOT_FOUND" ]; then
    print_error "EKS cluster not found. Please check the cluster name."
    exit 1
else
    print_warning "EKS cluster status: $CLUSTER_STATUS"
fi

# 2. Check Node Group Status
print_status "2. Checking node group status..."
NODEGROUP_STATUS=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.status' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$NODEGROUP_STATUS" == "ACTIVE" ]; then
    print_success "Node group is ACTIVE"
elif [ "$NODEGROUP_STATUS" == "CREATE_FAILED" ]; then
    print_error "Node group creation FAILED"
elif [ "$NODEGROUP_STATUS" == "NOT_FOUND" ]; then
    print_error "Node group not found"
    exit 1
else
    print_warning "Node group status: $NODEGROUP_STATUS"
fi

# 3. Check CloudFormation Stack Status
print_status "3. Checking CloudFormation stack status..."
STACK_NAME="eksctl-${CLUSTER_NAME}-nodegroup-${NODEGROUP_NAME}"
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$STACK_STATUS" == "CREATE_COMPLETE" ]; then
    print_success "CloudFormation stack is CREATE_COMPLETE"
elif [ "$STACK_STATUS" == "CREATE_FAILED" ]; then
    print_error "CloudFormation stack creation FAILED"
elif [ "$STACK_STATUS" == "NOT_FOUND" ]; then
    print_error "CloudFormation stack not found"
    exit 1
else
    print_warning "CloudFormation stack status: $STACK_STATUS"
fi

# 4. Check EC2 Instances
print_status "4. Checking EC2 instances..."
INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
    --region $REGION \
    --query 'Reservations[].Instances[?State.Name==`running`].[InstanceId,State.Name,LaunchTime]' \
    --output table 2>/dev/null || echo "No instances found")

echo "$INSTANCES"

# 5. Check Security Groups
print_status "5. Checking security groups..."
CLUSTER_SG=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text 2>/dev/null || echo "NOT_FOUND")
NODE_SG=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.resources.remoteAccessSecurityGroup' --output text 2>/dev/null || echo "NOT_FOUND")

echo "Cluster Security Group: $CLUSTER_SG"
echo "Node Security Group: $NODE_SG"

# 6. Check VPC and Subnets
print_status "6. Checking VPC and subnets..."
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || echo "NOT_FOUND")
SUBNETS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.subnetIds' --output text 2>/dev/null || echo "NOT_FOUND")

echo "VPC ID: $VPC_ID"
echo "Subnets: $SUBNETS"

# 7. Check IAM Roles
print_status "7. Checking IAM roles..."
NODE_ROLE=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query 'nodegroup.nodeRole' --output text 2>/dev/null || echo "NOT_FOUND")
echo "Node IAM Role: $NODE_ROLE"

# 8. Common Fixes
echo ""
echo -e "${BLUE}=== Common Fixes ===${NC}"

print_status "8. Attempting common fixes..."

# Fix 1: Delete and recreate node group
echo ""
print_warning "If the above checks show issues, try these fixes:"
echo "1. Delete the failed node group:"
echo "   eksctl delete nodegroup --cluster=$CLUSTER_NAME --name=$NODEGROUP_NAME --region=$REGION"
echo ""
echo "2. Recreate the node group:"
echo "   eksctl create nodegroup --cluster=$CLUSTER_NAME --name=$NODEGROUP_NAME --region=$REGION --node-type=t3.medium --nodes=2 --nodes-min=1 --nodes-max=4 --managed"
echo ""
echo "3. Or use the complete infrastructure script again:"
echo "   ./setup-complete-infrastructure.sh"
echo ""

# Fix 2: Check for specific issues
print_status "9. Checking for specific issues..."

# Check if subnets have proper tags
print_status "Checking subnet tags..."
SUBNET_IDS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.subnetIds' --output text 2>/dev/null)

if [ "$SUBNET_IDS" != "None" ] && [ -n "$SUBNET_IDS" ]; then
    for subnet in $SUBNET_IDS; do
        TAGS=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$subnet" --region $REGION --query 'Tags[?Key==`kubernetes.io/role/elb` || Key==`kubernetes.io/role/internal-elb`].{Key:Key,Value:Value}' --output table 2>/dev/null || echo "No tags")
        echo "Subnet $subnet tags:"
        echo "$TAGS"
    done
fi

# Check for CNI issues
print_status "Checking CNI configuration..."
CNI_PODS=$(kubectl get pods -n kube-system -l k8s-app=aws-node --output=name 2>/dev/null || echo "kubectl not configured or CNI pods not found")
echo "CNI Pods: $CNI_PODS"

echo ""
print_success "Troubleshooting complete. Review the output above for issues."
echo ""
print_warning "Most common causes of node creation failure:"
echo "- Insufficient IAM permissions"
echo "- Security group rules blocking communication"
echo "- Subnet configuration issues"
echo "- CNI (Container Network Interface) problems"
echo "- Resource limits (VPC limits, subnet IP exhaustion)" 