#!/bin/bash

# Infrastructure Cleanup Script
# Removes all resources created by setup-complete-infrastructure.sh

set -e

# Configuration
REGION="ap-southeast-2"
VPC_NAME="pv-syd-summit-demo-vpc"
CLUSTER_NAME="cymbalbank-cluster"
RDS_INSTANCE_NAME="pv-syd-summit-demo-rds"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local query=$3
    
    if aws $resource_type describe-$resource_type --$resource_name "$resource_name" --region $REGION --query "$query" --output text 2>/dev/null | grep -q .; then
        return 0
    else
        return 1
    fi
}

# Confirmation prompt
echo -e "${RED}⚠️  WARNING: This will delete ALL infrastructure resources!${NC}"
echo -e "${YELLOW}This includes:${NC}"
echo -e "  - EKS Cluster: $CLUSTER_NAME"
echo -e "  - RDS Instance: $RDS_INSTANCE_NAME"
echo -e "  - VPC: $VPC_NAME"
echo -e "  - All subnets, security groups, and route tables"
echo -e "  - All data will be permanently lost!"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}Cleanup cancelled.${NC}"
    exit 0
fi

print_status "Starting infrastructure cleanup..."

# 1. Delete EKS Cluster
print_status "Deleting EKS Cluster: $CLUSTER_NAME"
if resource_exists "eks" "cluster-name" "cluster.name"; then
    eksctl delete cluster --name $CLUSTER_NAME --region $REGION --wait
    print_success "EKS Cluster deleted"
else
    print_warning "EKS Cluster not found"
fi

# 2. Delete RDS Instance
print_status "Deleting RDS Instance: $RDS_INSTANCE_NAME"
if resource_exists "rds" "db-instance-identifier" "DBInstances[0].DBInstanceIdentifier"; then
    aws rds delete-db-instance \
        --db-instance-identifier $RDS_INSTANCE_NAME \
        --skip-final-snapshot \
        --delete-automated-backups \
        --region $REGION
    
    print_status "Waiting for RDS instance to be deleted..."
    aws rds wait db-instance-deleted \
        --db-instance-identifier $RDS_INSTANCE_NAME \
        --region $REGION
    print_success "RDS Instance deleted"
else
    print_warning "RDS Instance not found"
fi

# 3. Delete DB Subnet Group
print_status "Deleting DB Subnet Group"
if resource_exists "rds" "db-subnet-group-name" "DBSubnetGroups[0].DBSubnetGroupName" "${RDS_INSTANCE_NAME}-subnet-group"; then
    aws rds delete-db-subnet-group \
        --db-subnet-group-name "${RDS_INSTANCE_NAME}-subnet-group" \
        --region $REGION
    print_success "DB Subnet Group deleted"
else
    print_warning "DB Subnet Group not found"
fi

# 4. Get VPC ID
print_status "Getting VPC ID"
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=$VPC_NAME" \
    --region $REGION \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
    print_warning "VPC not found"
    exit 0
fi

print_status "Found VPC: $VPC_ID"

# 5. Delete Security Groups
print_status "Deleting Security Groups"

# Get security group IDs
SECURITY_GROUPS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
    --output text)

for SG_ID in $SECURITY_GROUPS; do
    print_status "Deleting Security Group: $SG_ID"
    aws ec2 delete-security-group --group-id $SG_ID --region $REGION 2>/dev/null || print_warning "Could not delete SG: $SG_ID"
done

print_success "Security Groups deleted"

# 6. Delete Subnets
print_status "Deleting Subnets"

# Get subnet IDs
SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --query 'Subnets[].SubnetId' \
    --output text)

for SUBNET_ID in $SUBNET_IDS; do
    print_status "Deleting Subnet: $SUBNET_ID"
    aws ec2 delete-subnet --subnet-id $SUBNET_ID --region $REGION 2>/dev/null || print_warning "Could not delete subnet: $SUBNET_ID"
done

print_success "Subnets deleted"

# 7. Delete Route Tables
print_status "Deleting Route Tables"

# Get route table IDs (excluding main route table)
ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=false" \
    --region $REGION \
    --query 'RouteTables[].RouteTableId' \
    --output text)

for RT_ID in $ROUTE_TABLE_IDS; do
    print_status "Deleting Route Table: $RT_ID"
    aws ec2 delete-route-table --route-table-id $RT_ID --region $REGION 2>/dev/null || print_warning "Could not delete route table: $RT_ID"
done

print_success "Route Tables deleted"

# 8. Delete Internet Gateway
print_status "Deleting Internet Gateway"

# Get Internet Gateway ID
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --region $REGION \
    --query 'InternetGateways[0].InternetGatewayId' \
    --output text)

if [ "$IGW_ID" != "None" ] && [ -n "$IGW_ID" ]; then
    aws ec2 detach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID --region $REGION
    aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID --region $REGION
    print_success "Internet Gateway deleted"
else
    print_warning "Internet Gateway not found"
fi

# 9. Delete VPC
print_status "Deleting VPC: $VPC_ID"
aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION
print_success "VPC deleted"

# 10. Clean up local files
print_status "Cleaning up local files"
rm -f rds-config.yaml
print_success "Local files cleaned up"

print_success "🎉 Infrastructure cleanup completed successfully!"
echo ""
echo -e "${GREEN}All resources have been deleted:${NC}"
echo -e "  ✅ EKS Cluster: $CLUSTER_NAME"
echo -e "  ✅ RDS Instance: $RDS_INSTANCE_NAME"
echo -e "  ✅ VPC: $VPC_NAME"
echo -e "  ✅ All subnets, security groups, and route tables"
echo ""
echo -e "${YELLOW}Note:${NC}"
echo -e "  - ECR repositories and images are not deleted"
echo -e "  - Any data in the databases has been permanently lost"
echo -e "  - CloudWatch logs may still exist"
echo -e "  - IAM roles and policies created by eksctl may still exist" 