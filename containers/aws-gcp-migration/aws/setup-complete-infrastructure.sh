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

# 1. Create VPC with CIDR 10.0.0.0/16
print_status "Creating VPC: $VPC_NAME"
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --region $REGION \
  --query 'Vpc.VpcId' \
  --output text)

aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME --region $REGION
print_success "VPC created: $VPC_ID"

# 2. Create Internet Gateway
print_status "Creating Internet Gateway"
IGW_ID=$(aws ec2 create-internet-gateway \
  --region $REGION \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value="${VPC_NAME}-igw" --region $REGION
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID --region $REGION
print_success "Internet Gateway created and attached: $IGW_ID"

# 3. Create Public Subnets (for EKS Control Plane and ALB)
print_status "Creating Public Subnets"
PUBLIC_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ${REGION}a \
  --region $REGION \
  --query 'Subnet.SubnetId' \
  --output text)

PUBLIC_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone ${REGION}b \
  --region $REGION \
  --query 'Subnet.SubnetId' \
  --output text)

aws ec2 create-tags --resources $PUBLIC_SUBNET_1 --tags Key=Name,Value="${VPC_NAME}-public-1" --region $REGION
aws ec2 create-tags --resources $PUBLIC_SUBNET_2 --tags Key=Name,Value="${VPC_NAME}-public-2" --region $REGION

# Enable auto-assign public IP for public subnets
aws ec2 modify-subnet-attribute --subnet-id $PUBLIC_SUBNET_1 --map-public-ip-on-launch --region $REGION
aws ec2 modify-subnet-attribute --subnet-id $PUBLIC_SUBNET_2 --map-public-ip-on-launch --region $REGION

print_success "Public Subnets created: $PUBLIC_SUBNET_1, $PUBLIC_SUBNET_2"

# 4. Create Private Subnets (for EKS Worker Nodes)
print_status "Creating Private Subnets"
PRIVATE_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.3.0/24 \
  --availability-zone ${REGION}a \
  --region $REGION \
  --query 'Subnet.SubnetId' \
  --output text)

PRIVATE_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.4.0/24 \
  --availability-zone ${REGION}b \
  --region $REGION \
  --query 'Subnet.SubnetId' \
  --output text)

aws ec2 create-tags --resources $PRIVATE_SUBNET_1 --tags Key=Name,Value="${VPC_NAME}-private-1" --region $REGION
aws ec2 create-tags --resources $PRIVATE_SUBNET_2 --tags Key=Name,Value="${VPC_NAME}-private-2" --region $REGION

print_success "Private Subnets created: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2"

# 5. Create Database Subnets (for RDS)
print_status "Creating Database Subnets"
DB_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.5.0/24 \
  --availability-zone ${REGION}a \
  --region $REGION \
  --query 'Subnet.SubnetId' \
  --output text)

DB_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.6.0/24 \
  --availability-zone ${REGION}b \
  --region $REGION \
  --query 'Subnet.SubnetId' \
  --output text)

aws ec2 create-tags --resources $DB_SUBNET_1 --tags Key=Name,Value="${VPC_NAME}-db-1" --region $REGION
aws ec2 create-tags --resources $DB_SUBNET_2 --tags Key=Name,Value="${VPC_NAME}-db-2" --region $REGION

print_success "Database Subnets created: $DB_SUBNET_1, $DB_SUBNET_2"

# 6. Create Route Tables
print_status "Creating Route Tables"

# Public Route Table
PUBLIC_RT=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-tags --resources $PUBLIC_RT --tags Key=Name,Value="${VPC_NAME}-public-rt" --region $REGION

# Add route to Internet Gateway
aws ec2 create-route \
  --route-table-id $PUBLIC_RT \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID \
  --region $REGION

# Associate public subnets with public route table
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_1 --route-table-id $PUBLIC_RT --region $REGION
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_2 --route-table-id $PUBLIC_RT --region $REGION

# Private Route Table
PRIVATE_RT=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-tags --resources $PRIVATE_RT --tags Key=Name,Value="${VPC_NAME}-private-rt" --region $REGION

# Associate private subnets with private route table
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_1 --route-table-id $PRIVATE_RT --region $REGION
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_2 --route-table-id $PRIVATE_RT --region $REGION

# Associate database subnets with private route table
aws ec2 associate-route-table --subnet-id $DB_SUBNET_1 --route-table-id $PRIVATE_RT --region $REGION
aws ec2 associate-route-table --subnet-id $DB_SUBNET_2 --route-table-id $PRIVATE_RT --region $REGION

print_success "Route Tables created and configured"

# 7. Create Security Groups
print_status "Creating Security Groups"

# EKS Cluster Security Group
EKS_CLUSTER_SG=$(aws ec2 create-security-group \
  --group-name "${CLUSTER_NAME}-cluster-sg" \
  --description "Security group for EKS cluster control plane" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' \
  --output text)

aws ec2 create-tags --resources $EKS_CLUSTER_SG --tags Key=Name,Value="${CLUSTER_NAME}-cluster-sg" --region $REGION

# EKS Node Security Group
EKS_NODE_SG=$(aws ec2 create-security-group \
  --group-name "${CLUSTER_NAME}-node-sg" \
  --description "Security group for EKS worker nodes" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' \
  --output text)

aws ec2 create-tags --resources $EKS_NODE_SG --tags Key=Name,Value="${CLUSTER_NAME}-node-sg" --region $REGION

# RDS Security Group
RDS_SG=$(aws ec2 create-security-group \
  --group-name "${RDS_INSTANCE_NAME}-sg" \
  --description "Security group for RDS instance" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' \
  --output text)

aws ec2 create-tags --resources $RDS_SG --tags Key=Name,Value="${RDS_INSTANCE_NAME}-sg" --region $REGION

# ALB Security Group
ALB_SG=$(aws ec2 create-security-group \
  --group-name "${CLUSTER_NAME}-alb-sg" \
  --description "Security group for Application Load Balancer" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' \
  --output text)

aws ec2 create-tags --resources $ALB_SG --tags Key=Name,Value="${CLUSTER_NAME}-alb-sg" --region $REGION

print_success "Security Groups created"

# 8. Configure Security Group Rules
print_status "Configuring Security Group Rules"

# EKS Cluster SG Rules
aws ec2 authorize-security-group-ingress \
  --group-id $EKS_CLUSTER_SG \
  --protocol tcp \
  --port 443 \
  --source-group $EKS_NODE_SG \
  --region $REGION

# EKS Node SG Rules
aws ec2 authorize-security-group-ingress \
  --group-id $EKS_NODE_SG \
  --protocol all \
  --source-group $EKS_NODE_SG \
  --region $REGION

aws ec2 authorize-security-group-ingress \
  --group-id $EKS_NODE_SG \
  --protocol tcp \
  --port 443 \
  --source-group $EKS_CLUSTER_SG \
  --region $REGION

aws ec2 authorize-security-group-ingress \
  --group-id $EKS_NODE_SG \
  --protocol tcp \
  --port 8080 \
  --source-group $ALB_SG \
  --region $REGION

# RDS SG Rules
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $EKS_NODE_SG \
  --region $REGION

# Allow access from your current IP for management
YOUR_IP=$(curl -s ifconfig.me)
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 5432 \
  --cidr "${YOUR_IP}/32" \
  --region $REGION

# ALB SG Rules
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp \
  --port 80 \
  --cidr "0.0.0.0/0" \
  --region $REGION

aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp \
  --port 443 \
  --cidr "0.0.0.0/0" \
  --region $REGION

print_success "Security Group Rules configured"

# 9. Create DB Subnet Group
print_status "Creating DB Subnet Group"
aws rds create-db-subnet-group \
  --db-subnet-group-name "${RDS_INSTANCE_NAME}-subnet-group" \
  --db-subnet-group-description "Subnet group for RDS instance" \
  --subnet-ids $DB_SUBNET_1 $DB_SUBNET_2 \
  --region $REGION

print_success "DB Subnet Group created"

# 10. Create RDS Instance
print_status "Creating RDS Instance"
RDS_ENDPOINT=$(aws rds create-db-instance \
  --db-instance-identifier $RDS_INSTANCE_NAME \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 15.4 \
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

# 11. Create EKS Cluster
print_status "Creating EKS Cluster"
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