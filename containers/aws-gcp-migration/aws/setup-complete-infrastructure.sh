#!/bin/bash

# Complete AWS Infrastructure Setup Script
# Creates VPC, EKS Cluster, RDS Instance, and all necessary components
# Region: Sydney (ap-southeast-2)

set -e

# Configuration
REGION="ap-southeast-2"
VPC_NAME="pv-syd-summit-demo-vpc"
CLUSTER_NAME="cymbalbank-cluster"
RDS_INSTANCE_NAME="pv-syd-summit-demo-rds"
DB_NAME="cymbalbank"
DB_USERNAME="postgres"
DB_PASSWORD="Chiapet22!"

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

# Function to get the latest available PostgreSQL version
get_latest_postgres_version() {
    local latest_version=$(aws rds describe-db-engine-versions \
        --engine postgres \
        --region $REGION \
        --query 'DBEngineVersions[?SupportsStorageEncryption==`true`].EngineVersion' \
        --output text | tr '\t' '\n' | sort -V | tail -1)
    
    echo $latest_version
}

# Function to check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 is not installed. Please install it first."
        exit 1
    fi
}

# Check prerequisites
print_status "Checking prerequisites..."
check_command "aws"
check_command "kubectl"
check_command "eksctl"

# Check AWS CLI configuration
print_status "Checking AWS CLI configuration..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_success "Using AWS Account: $ACCOUNT_ID"

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

# Function to check if VPC exists
vpc_exists() {
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$VPC_NAME" \
        --region $REGION \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    if [ "$vpc_id" != "None" ] && [ -n "$vpc_id" ]; then
        echo $vpc_id
        return 0
    else
        return 1
    fi
}

# Function to check if security group exists
security_group_exists() {
    local sg_name=$1
    local sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$sg_name" "Name=vpc-id,Values=$VPC_ID" \
        --region $REGION \
        --query 'SecurityGroups[0].GroupId' \
        --output text)
    
    if [ "$sg_id" != "None" ] && [ -n "$sg_id" ]; then
        echo $sg_id
        return 0
    else
        return 1
    fi
}

# Function to check if subnet exists
subnet_exists() {
    local subnet_cidr=$1
    local subnet_id=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=cidr-block,Values=$subnet_cidr" \
        --region $REGION \
        --query 'Subnets[0].SubnetId' \
        --output text)
    
    if [ "$subnet_id" != "None" ] && [ -n "$subnet_id" ]; then
        echo $subnet_id
        return 0
    else
        return 1
    fi
}

# Function to check if route table association exists
route_table_association_exists() {
    local subnet_id=$1
    local route_table_id=$2
    
    local association_id=$(aws ec2 describe-route-tables \
        --route-table-ids $route_table_id \
        --region $REGION \
        --query "RouteTables[0].Associations[?SubnetId=='$subnet_id'].RouteTableAssociationId" \
        --output text)
    
    if [ "$association_id" != "None" ] && [ -n "$association_id" ]; then
        echo $association_id
        return 0
    else
        return 1
    fi
}

# 1. Create VPC with CIDR 10.0.0.0/16
print_status "Creating VPC: $VPC_NAME"

# Check if VPC already exists
if VPC_ID=$(vpc_exists); then
    print_warning "VPC already exists: $VPC_ID"
else
    VPC_ID=$(aws ec2 create-vpc \
      --cidr-block 10.0.0.0/16 \
      --region $REGION \
      --query 'Vpc.VpcId' \
      --output text)

    aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME --region $REGION
    print_success "VPC created: $VPC_ID"
fi

# 2. Create Internet Gateway
print_status "Creating Internet Gateway"

# Check if Internet Gateway already exists
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=tag:Name,Values=${VPC_NAME}-igw" \
    --region $REGION \
    --query 'InternetGateways[0].InternetGatewayId' \
    --output text)

if [ "$IGW_ID" == "None" ] || [ -z "$IGW_ID" ]; then
    IGW_ID=$(aws ec2 create-internet-gateway \
      --region $REGION \
      --query 'InternetGateway.InternetGatewayId' \
      --output text)

    aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value="${VPC_NAME}-igw" --region $REGION
    print_success "Internet Gateway created: $IGW_ID"
else
    print_warning "Internet Gateway already exists: $IGW_ID"
fi

# Check if IGW is already attached to VPC
if ! aws ec2 describe-internet-gateways --internet-gateway-ids $IGW_ID --region $REGION --query 'InternetGateways[0].Attachments[0].VpcId' --output text | grep -q $VPC_ID; then
    aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID --region $REGION
    print_success "Internet Gateway attached to VPC"
else
    print_warning "Internet Gateway already attached to VPC"
fi

# 3. Create Public Subnets (for EKS Control Plane and ALB)
print_status "Creating Public Subnets"

# Check if public subnets already exist
if PUBLIC_SUBNET_1=$(subnet_exists "10.0.1.0/24"); then
    print_warning "Public Subnet 1 already exists: $PUBLIC_SUBNET_1"
else
    PUBLIC_SUBNET_1=$(aws ec2 create-subnet \
      --vpc-id $VPC_ID \
      --cidr-block 10.0.1.0/24 \
      --availability-zone ${REGION}a \
      --region $REGION \
      --query 'Subnet.SubnetId' \
      --output text)

    aws ec2 create-tags --resources $PUBLIC_SUBNET_1 --tags Key=Name,Value="${VPC_NAME}-public-1" --region $REGION
    print_success "Public Subnet 1 created: $PUBLIC_SUBNET_1"
fi

if PUBLIC_SUBNET_2=$(subnet_exists "10.0.2.0/24"); then
    print_warning "Public Subnet 2 already exists: $PUBLIC_SUBNET_2"
else
    PUBLIC_SUBNET_2=$(aws ec2 create-subnet \
      --vpc-id $VPC_ID \
      --cidr-block 10.0.2.0/24 \
      --availability-zone ${REGION}b \
      --region $REGION \
      --query 'Subnet.SubnetId' \
      --output text)

    aws ec2 create-tags --resources $PUBLIC_SUBNET_2 --tags Key=Name,Value="${VPC_NAME}-public-2" --region $REGION
    print_success "Public Subnet 2 created: $PUBLIC_SUBNET_2"
fi

# Enable auto-assign public IP for public subnets
aws ec2 modify-subnet-attribute --subnet-id $PUBLIC_SUBNET_1 --map-public-ip-on-launch --region $REGION
aws ec2 modify-subnet-attribute --subnet-id $PUBLIC_SUBNET_2 --map-public-ip-on-launch --region $REGION

print_success "Public Subnets configured: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2"

# 4. Create Private Subnets (for EKS Worker Nodes)
print_status "Creating Private Subnets"

# Check if private subnets already exist
if PRIVATE_SUBNET_1=$(subnet_exists "10.0.3.0/24"); then
    print_warning "Private Subnet 1 already exists: $PRIVATE_SUBNET_1"
else
    PRIVATE_SUBNET_1=$(aws ec2 create-subnet \
      --vpc-id $VPC_ID \
      --cidr-block 10.0.3.0/24 \
      --availability-zone ${REGION}a \
      --region $REGION \
      --query 'Subnet.SubnetId' \
      --output text)

    aws ec2 create-tags --resources $PRIVATE_SUBNET_1 --tags Key=Name,Value="${VPC_NAME}-private-1" --region $REGION
    print_success "Private Subnet 1 created: $PRIVATE_SUBNET_1"
fi

if PRIVATE_SUBNET_2=$(subnet_exists "10.0.4.0/24"); then
    print_warning "Private Subnet 2 already exists: $PRIVATE_SUBNET_2"
else
    PRIVATE_SUBNET_2=$(aws ec2 create-subnet \
      --vpc-id $VPC_ID \
      --cidr-block 10.0.4.0/24 \
      --availability-zone ${REGION}b \
      --region $REGION \
      --query 'Subnet.SubnetId' \
      --output text)

    aws ec2 create-tags --resources $PRIVATE_SUBNET_2 --tags Key=Name,Value="${VPC_NAME}-private-2" --region $REGION
    print_success "Private Subnet 2 created: $PRIVATE_SUBNET_2"
fi

print_success "Private Subnets configured: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"

# 5. Create Database Subnets (for RDS)
print_status "Creating Database Subnets"

# Check if database subnets already exist
if DB_SUBNET_1=$(subnet_exists "10.0.5.0/24"); then
    print_warning "Database Subnet 1 already exists: $DB_SUBNET_1"
else
    DB_SUBNET_1=$(aws ec2 create-subnet \
      --vpc-id $VPC_ID \
      --cidr-block 10.0.5.0/24 \
      --availability-zone ${REGION}a \
      --region $REGION \
      --query 'Subnet.SubnetId' \
      --output text)

    aws ec2 create-tags --resources $DB_SUBNET_1 --tags Key=Name,Value="${VPC_NAME}-db-1" --region $REGION
    print_success "Database Subnet 1 created: $DB_SUBNET_1"
fi

if DB_SUBNET_2=$(subnet_exists "10.0.6.0/24"); then
    print_warning "Database Subnet 2 already exists: $DB_SUBNET_2"
else
    DB_SUBNET_2=$(aws ec2 create-subnet \
      --vpc-id $VPC_ID \
      --cidr-block 10.0.6.0/24 \
      --availability-zone ${REGION}b \
      --region $REGION \
      --query 'Subnet.SubnetId' \
      --output text)

    aws ec2 create-tags --resources $DB_SUBNET_2 --tags Key=Name,Value="${VPC_NAME}-db-2" --region $REGION
    print_success "Database Subnet 2 created: $DB_SUBNET_2"
fi

print_success "Database Subnets configured: $DB_SUBNET_1, $DB_SUBNET_2"

# 6. Create Route Tables
print_status "Creating Route Tables"

# Check if route tables already exist
PUBLIC_RT=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${VPC_NAME}-public-rt" \
    --region $REGION \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

if [ "$PUBLIC_RT" == "None" ] || [ -z "$PUBLIC_RT" ]; then
    PUBLIC_RT=$(aws ec2 create-route-table \
      --vpc-id $VPC_ID \
      --region $REGION \
      --query 'RouteTable.RouteTableId' \
      --output text)

    aws ec2 create-tags --resources $PUBLIC_RT --tags Key=Name,Value="${VPC_NAME}-public-rt" --region $REGION
    print_success "Public Route Table created: $PUBLIC_RT"
else
    print_warning "Public Route Table already exists: $PUBLIC_RT"
fi

# Add route to Internet Gateway (only if it doesn't exist)
if ! aws ec2 describe-route-tables --route-table-ids $PUBLIC_RT --region $REGION --query 'RouteTables[0].Routes[?GatewayId!=`null`].GatewayId' --output text | grep -q $IGW_ID; then
    aws ec2 create-route \
      --route-table-id $PUBLIC_RT \
      --destination-cidr-block 0.0.0.0/0 \
      --gateway-id $IGW_ID \
      --region $REGION
    print_success "Internet Gateway route added to public route table"
else
    print_warning "Internet Gateway route already exists in public route table"
fi

# Associate public subnets with public route table
if ! route_table_association_exists $PUBLIC_SUBNET_1 $PUBLIC_RT; then
    aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_1 --route-table-id $PUBLIC_RT --region $REGION
    print_success "Public Subnet 1 associated with public route table"
else
    print_warning "Public Subnet 1 already associated with public route table"
fi

if ! route_table_association_exists $PUBLIC_SUBNET_2 $PUBLIC_RT; then
    aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_2 --route-table-id $PUBLIC_RT --region $REGION
    print_success "Public Subnet 2 associated with public route table"
else
    print_warning "Public Subnet 2 already associated with public route table"
fi

# Private Route Table
PRIVATE_RT=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${VPC_NAME}-private-rt" \
    --region $REGION \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

if [ "$PRIVATE_RT" == "None" ] || [ -z "$PRIVATE_RT" ]; then
    PRIVATE_RT=$(aws ec2 create-route-table \
      --vpc-id $VPC_ID \
      --region $REGION \
      --query 'RouteTable.RouteTableId' \
      --output text)

    aws ec2 create-tags --resources $PRIVATE_RT --tags Key=Name,Value="${VPC_NAME}-private-rt" --region $REGION
    print_success "Private Route Table created: $PRIVATE_RT"
else
    print_warning "Private Route Table already exists: $PRIVATE_RT"
fi

# Associate private subnets with private route table
if ! route_table_association_exists $PRIVATE_SUBNET_1 $PRIVATE_RT; then
    aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_1 --route-table-id $PRIVATE_RT --region $REGION
    print_success "Private Subnet 1 associated with private route table"
else
    print_warning "Private Subnet 1 already associated with private route table"
fi

if ! route_table_association_exists $PRIVATE_SUBNET_2 $PRIVATE_RT; then
    aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_2 --route-table-id $PRIVATE_RT --region $REGION
    print_success "Private Subnet 2 associated with private route table"
else
    print_warning "Private Subnet 2 already associated with private route table"
fi

# Associate database subnets with private route table
if ! route_table_association_exists $DB_SUBNET_1 $PRIVATE_RT; then
    aws ec2 associate-route-table --subnet-id $DB_SUBNET_1 --route-table-id $PRIVATE_RT --region $REGION
    print_success "Database Subnet 1 associated with private route table"
else
    print_warning "Database Subnet 1 already associated with private route table"
fi

if ! route_table_association_exists $DB_SUBNET_2 $PRIVATE_RT; then
    aws ec2 associate-route-table --subnet-id $DB_SUBNET_2 --route-table-id $PRIVATE_RT --region $REGION
    print_success "Database Subnet 2 associated with private route table"
else
    print_warning "Database Subnet 2 already associated with private route table"
fi

print_success "Route Tables created and configured"

# 7. Create Security Groups
print_status "Creating Security Groups"

# EKS Cluster Security Group
if EKS_CLUSTER_SG=$(security_group_exists "${CLUSTER_NAME}-cluster-sg"); then
    print_warning "EKS Cluster Security Group already exists: $EKS_CLUSTER_SG"
else
    EKS_CLUSTER_SG=$(aws ec2 create-security-group \
      --group-name "${CLUSTER_NAME}-cluster-sg" \
      --description "Security group for EKS cluster control plane" \
      --vpc-id $VPC_ID \
      --region $REGION \
      --query 'GroupId' \
      --output text)

    aws ec2 create-tags --resources $EKS_CLUSTER_SG --tags Key=Name,Value="${CLUSTER_NAME}-cluster-sg" --region $REGION
    print_success "EKS Cluster Security Group created: $EKS_CLUSTER_SG"
fi

# EKS Node Security Group
if EKS_NODE_SG=$(security_group_exists "${CLUSTER_NAME}-node-sg"); then
    print_warning "EKS Node Security Group already exists: $EKS_NODE_SG"
else
    EKS_NODE_SG=$(aws ec2 create-security-group \
      --group-name "${CLUSTER_NAME}-node-sg" \
      --description "Security group for EKS worker nodes" \
      --vpc-id $VPC_ID \
      --region $REGION \
      --query 'GroupId' \
      --output text)

    aws ec2 create-tags --resources $EKS_NODE_SG --tags Key=Name,Value="${CLUSTER_NAME}-node-sg" --region $REGION
    print_success "EKS Node Security Group created: $EKS_NODE_SG"
fi

# RDS Security Group
if RDS_SG=$(security_group_exists "${RDS_INSTANCE_NAME}-sg"); then
    print_warning "RDS Security Group already exists: $RDS_SG"
else
    RDS_SG=$(aws ec2 create-security-group \
      --group-name "${RDS_INSTANCE_NAME}-sg" \
      --description "Security group for RDS instance" \
      --vpc-id $VPC_ID \
      --region $REGION \
      --query 'GroupId' \
      --output text)

    aws ec2 create-tags --resources $RDS_SG --tags Key=Name,Value="${RDS_INSTANCE_NAME}-sg" --region $REGION
    print_success "RDS Security Group created: $RDS_SG"
fi

# ALB Security Group
if ALB_SG=$(security_group_exists "${CLUSTER_NAME}-alb-sg"); then
    print_warning "ALB Security Group already exists: $ALB_SG"
else
    ALB_SG=$(aws ec2 create-security-group \
      --group-name "${CLUSTER_NAME}-alb-sg" \
      --description "Security group for Application Load Balancer" \
      --vpc-id $VPC_ID \
      --region $REGION \
      --query 'GroupId' \
      --output text)

    aws ec2 create-tags --resources $ALB_SG --tags Key=Name,Value="${CLUSTER_NAME}-alb-sg" --region $REGION
    print_success "ALB Security Group created: $ALB_SG"
fi

print_success "Security Groups created"

# 8. Configure Security Group Rules
print_status "Configuring Security Group Rules"

# Function to check if security group rule exists
security_group_rule_exists() {
    local sg_id=$1
    local protocol=$2
    local port=$3
    local source=$4
    
    local rule_exists=$(aws ec2 describe-security-groups \
        --group-ids $sg_id \
        --region $REGION \
        --query "SecurityGroups[0].IpPermissions[?Protocol=='$protocol' && FromPort==$port && ToPort==$port].UserIdGroupPairs[?GroupId=='$source'].GroupId" \
        --output text)
    
    if [ "$rule_exists" != "None" ] && [ -n "$rule_exists" ]; then
        return 0
    else
        return 1
    fi
}

# EKS Cluster SG Rules
if ! security_group_rule_exists $EKS_CLUSTER_SG "tcp" 443 $EKS_NODE_SG; then
    aws ec2 authorize-security-group-ingress \
      --group-id $EKS_CLUSTER_SG \
      --protocol tcp \
      --port 443 \
      --source-group $EKS_NODE_SG \
      --region $REGION
    print_success "EKS Cluster SG rule added"
else
    print_warning "EKS Cluster SG rule already exists"
fi

# EKS Node SG Rules
if ! security_group_rule_exists $EKS_NODE_SG "tcp" -1 $EKS_NODE_SG; then
    aws ec2 authorize-security-group-ingress \
      --group-id $EKS_NODE_SG \
      --protocol all \
      --source-group $EKS_NODE_SG \
      --region $REGION
    print_success "EKS Node SG self-referencing rule added"
else
    print_warning "EKS Node SG self-referencing rule already exists"
fi

if ! security_group_rule_exists $EKS_NODE_SG "tcp" 443 $EKS_CLUSTER_SG; then
    aws ec2 authorize-security-group-ingress \
      --group-id $EKS_NODE_SG \
      --protocol tcp \
      --port 443 \
      --source-group $EKS_CLUSTER_SG \
      --region $REGION
    print_success "EKS Node SG cluster access rule added"
else
    print_warning "EKS Node SG cluster access rule already exists"
fi

if ! security_group_rule_exists $EKS_NODE_SG "tcp" 8080 $ALB_SG; then
    aws ec2 authorize-security-group-ingress \
      --group-id $EKS_NODE_SG \
      --protocol tcp \
      --port 8080 \
      --source-group $ALB_SG \
      --region $REGION
    print_success "EKS Node SG ALB access rule added"
else
    print_warning "EKS Node SG ALB access rule already exists"
fi

# RDS SG Rules
if ! security_group_rule_exists $RDS_SG "tcp" 5432 $EKS_NODE_SG; then
    aws ec2 authorize-security-group-ingress \
      --group-id $RDS_SG \
      --protocol tcp \
      --port 5432 \
      --source-group $EKS_NODE_SG \
      --region $REGION
    print_success "RDS SG EKS access rule added"
else
    print_warning "RDS SG EKS access rule already exists"
fi

# Allow access from your current IP for management
YOUR_IP=$(curl -s ifconfig.me)
if ! aws ec2 describe-security-groups --group-ids $RDS_SG --region $REGION --query "SecurityGroups[0].IpPermissions[?Protocol=='tcp' && FromPort==5432 && ToPort==5432].IpRanges[?CidrIp=='${YOUR_IP}/32'].CidrIp" --output text | grep -q "${YOUR_IP}/32"; then
    aws ec2 authorize-security-group-ingress \
      --group-id $RDS_SG \
      --protocol tcp \
      --port 5432 \
      --cidr "${YOUR_IP}/32" \
      --region $REGION
    print_success "RDS SG management IP access rule added"
else
    print_warning "RDS SG management IP access rule already exists"
fi

# ALB SG Rules
if ! aws ec2 describe-security-groups --group-ids $ALB_SG --region $REGION --query "SecurityGroups[0].IpPermissions[?Protocol=='tcp' && FromPort==80 && ToPort==80].IpRanges[?CidrIp=='0.0.0.0/0'].CidrIp" --output text | grep -q "0.0.0.0/0"; then
    aws ec2 authorize-security-group-ingress \
      --group-id $ALB_SG \
      --protocol tcp \
      --port 80 \
      --cidr "0.0.0.0/0" \
      --region $REGION
    print_success "ALB SG HTTP access rule added"
else
    print_warning "ALB SG HTTP access rule already exists"
fi

if ! aws ec2 describe-security-groups --group-ids $ALB_SG --region $REGION --query "SecurityGroups[0].IpPermissions[?Protocol=='tcp' && FromPort==443 && ToPort==443].IpRanges[?CidrIp=='0.0.0.0/0'].CidrIp" --output text | grep -q "0.0.0.0/0"; then
    aws ec2 authorize-security-group-ingress \
      --group-id $ALB_SG \
      --protocol tcp \
      --port 443 \
      --cidr "0.0.0.0/0" \
      --region $REGION
    print_success "ALB SG HTTPS access rule added"
else
    print_warning "ALB SG HTTPS access rule already exists"
fi

print_success "Security Group Rules configured"

# 9. Create DB Subnet Group
print_status "Creating DB Subnet Group"

# Check if DB subnet group already exists
if resource_exists "rds" "db-subnet-group-name" "DBSubnetGroups[0].DBSubnetGroupName" "${RDS_INSTANCE_NAME}-subnet-group"; then
    print_warning "DB Subnet Group already exists: ${RDS_INSTANCE_NAME}-subnet-group"
else
    aws rds create-db-subnet-group \
      --db-subnet-group-name "${RDS_INSTANCE_NAME}-subnet-group" \
      --db-subnet-group-description "Subnet group for RDS instance" \
      --subnet-ids $DB_SUBNET_1 $DB_SUBNET_2 \
      --region $REGION
    print_success "DB Subnet Group created"
fi

# 10. Create RDS Instance
print_status "Creating RDS Instance"

# Check if RDS instance already exists
if resource_exists "rds" "db-instance-identifier" "DBInstances[0].DBInstanceIdentifier" "$RDS_INSTANCE_NAME"; then
    print_warning "RDS Instance already exists: $RDS_INSTANCE_NAME"
    RDS_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier $RDS_INSTANCE_NAME \
        --region $REGION \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    print_success "Using existing RDS endpoint: $RDS_ENDPOINT"
else
    # Get the latest available PostgreSQL version
    print_status "Checking available PostgreSQL versions..."
    POSTGRES_VERSION=$(get_latest_postgres_version)
    print_success "Using PostgreSQL version: $POSTGRES_VERSION"

    RDS_ENDPOINT=$(aws rds create-db-instance \
      --db-instance-identifier $RDS_INSTANCE_NAME \
      --db-instance-class db.t3.micro \
      --engine postgres \
      --engine-version $POSTGRES_VERSION \
      --master-username $DB_USERNAME \
      --master-user-password $DB_PASSWORD \
      --allocated-storage 20 \
      --storage-type gp2 \
      --db-subnet-group-name "${RDS_INSTANCE_NAME}-subnet-group" \
      --vpc-security-group-ids $RDS_SG \
      --backup-retention-period 7 \
      --storage-encrypted \
      --region $REGION \
      --query 'DBInstance.Endpoint.Address' \
      --output text)

    print_success "RDS Instance created: $RDS_ENDPOINT"

    # Wait for RDS to be available
    print_status "Waiting for RDS instance to be available..."
    aws rds wait db-instance-available \
      --db-instance-identifier $RDS_INSTANCE_NAME \
      --region $REGION

    print_success "RDS instance is available"
fi

# 11. Create EKS Cluster
print_status "Creating EKS Cluster"

# Check if EKS cluster already exists
if aws eks describe-cluster --name $CLUSTER_NAME --region $REGION &>/dev/null; then
    print_warning "EKS Cluster already exists: $CLUSTER_NAME"
else
    eksctl create cluster \
      --name $CLUSTER_NAME \
      --region $REGION \
      --vpc-private-subnets $PRIVATE_SUBNET_1,$PRIVATE_SUBNET_2 \
      --vpc-public-subnets $PUBLIC_SUBNET_1,$PUBLIC_SUBNET_2 \
      --nodegroup-name standard-workers \
      --node-type t3.medium \
      --nodes 2 \
      --nodes-min 1 \
      --nodes-max 4 \
      --managed \
      --cluster-endpoint-public-access \
      --cluster-endpoint-private-access \
      --cluster-security-groups $EKS_CLUSTER_SG \
      --node-security-groups $EKS_NODE_SG \
      --ssh-access \
      --ssh-public-key my-key \
      --external-dns-access \
      --full-ecr-access \
      --appmesh-access \
      --alb-ingress-access

    print_success "EKS Cluster created"
fi

# 12. Update kubeconfig
print_status "Updating kubeconfig"
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

# 13. Create databases in RDS
print_status "Creating databases in RDS instance"
PGPASSWORD=$DB_PASSWORD psql -h $RDS_ENDPOINT -p 5432 -U $DB_USERNAME -d postgres -c "CREATE DATABASE \"accounts-db\";" 2>/dev/null || print_warning "accounts-db might already exist"
PGPASSWORD=$DB_PASSWORD psql -h $RDS_ENDPOINT -p 5432 -U $DB_USERNAME -d postgres -c "CREATE DATABASE \"ledger-db\";" 2>/dev/null || print_warning "ledger-db might already exist"

print_success "Databases created"

# 14. Create ConfigMap with updated RDS endpoint
print_status "Creating ConfigMap with RDS endpoint"
cat > rds-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: accounts-db-config
  labels:
    app: accounts-db
data:
  ACCOUNTS_DB_URI: postgresql://$DB_USERNAME:$DB_PASSWORD@$RDS_ENDPOINT:5432/accounts-db
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ledger-db-config
  labels:
    app: postgres
data:
  POSTGRES_DB: ledger-db
  POSTGRES_USER: $DB_USERNAME
  POSTGRES_PASSWORD: $DB_PASSWORD
  SPRING_DATASOURCE_URL: jdbc:postgresql://$RDS_ENDPOINT:5432/ledger-db
  SPRING_DATASOURCE_USERNAME: $DB_USERNAME
  SPRING_DATASOURCE_PASSWORD: $DB_PASSWORD
EOF

kubectl apply -f rds-config.yaml
print_success "ConfigMap created with RDS endpoint"

# 15. Output summary
print_success "🎉 Infrastructure setup completed successfully!"
echo ""
echo -e "${BLUE}Infrastructure Summary:${NC}"
echo -e "  VPC: $VPC_ID ($VPC_NAME)"
echo -e "  EKS Cluster: $CLUSTER_NAME"
echo -e "  RDS Instance: $RDS_INSTANCE_NAME"
echo -e "  RDS Endpoint: $RDS_ENDPOINT"
echo -e "  Region: $REGION"
echo ""
echo -e "${BLUE}Security Groups:${NC}"
echo -e "  EKS Cluster: $EKS_CLUSTER_SG"
echo -e "  EKS Nodes: $EKS_NODE_SG"
echo -e "  RDS: $RDS_SG"
echo -e "  ALB: $ALB_SG"
echo ""
echo -e "${BLUE}Subnets:${NC}"
echo -e "  Public: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2"
echo -e "  Private: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"
echo -e "  Database: $DB_SUBNET_1, $DB_SUBNET_2"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Run: ./ecr_build_push.sh"
echo -e "  2. Run: kubectl apply -f kubernetes/app-manifests/"
echo -e "  3. Run: kubectl apply -f kubernetes/sql/"
echo -e "  4. Access your application via the ALB URL"
echo ""
echo -e "${YELLOW}Database Credentials:${NC}"
echo -e "  Username: $DB_USERNAME"
echo -e "  Password: $DB_PASSWORD"
echo -e "  Accounts DB: accounts-db"
echo -e "  Ledger DB: ledger-db"
echo ""
echo -e "${RED}⚠️  Important:${NC}"
echo -e "  - Store database credentials securely in production"
echo -e "  - Consider using AWS Secrets Manager"
echo -e "  - Review security group rules for production use"
echo -e "  - Enable CloudTrail and VPC Flow Logs for monitoring" 