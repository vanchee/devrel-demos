#!/bin/bash

# AWS Security Groups Configuration for EKS + RDS
# This script demonstrates best practices for security group configuration

set -e

# Configuration
REGION="ap-southeast-2"
VPC_ID="vpc-xxxxxxxxx"  # Replace with your VPC ID
CLUSTER_NAME="cymbalbank-cluster"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔒 Creating Security Groups for EKS + RDS...${NC}"

# 1. EKS Cluster Security Group
echo -e "${YELLOW}Creating EKS Cluster Security Group...${NC}"
EKS_CLUSTER_SG=$(aws ec2 create-security-group \
  --group-name "${CLUSTER_NAME}-cluster-sg" \
  --description "Security group for EKS cluster control plane" \
  --vpc-id "$VPC_ID" \
  --region "$REGION" \
  --query 'GroupId' \
  --output text)

echo -e "${GREEN}✅ EKS Cluster SG: $EKS_CLUSTER_SG${NC}"

# Allow EKS control plane to communicate with worker nodes
aws ec2 authorize-security-group-ingress \
  --group-id "$EKS_CLUSTER_SG" \
  --protocol tcp \
  --port 443 \
  --source-group "$EKS_CLUSTER_SG" \
  --region "$REGION"

# 2. EKS Node Security Group
echo -e "${YELLOW}Creating EKS Node Security Group...${NC}"
EKS_NODE_SG=$(aws ec2 create-security-group \
  --group-name "${CLUSTER_NAME}-node-sg" \
  --description "Security group for EKS worker nodes" \
  --vpc-id "$VPC_ID" \
  --region "$REGION" \
  --query 'GroupId' \
  --output text)

echo -e "${GREEN}✅ EKS Node SG: $EKS_NODE_SG${NC}"

# Allow all traffic within the node group
aws ec2 authorize-security-group-ingress \
  --group-id "$EKS_NODE_SG" \
  --protocol all \
  --source-group "$EKS_NODE_SG" \
  --region "$REGION"

# Allow EKS control plane to communicate with worker nodes
aws ec2 authorize-security-group-ingress \
  --group-id "$EKS_NODE_SG" \
  --protocol tcp \
  --port 443 \
  --source-group "$EKS_CLUSTER_SG" \
  --region "$REGION"

# Allow worker nodes to communicate with EKS control plane
aws ec2 authorize-security-group-ingress \
  --group-id "$EKS_NODE_SG" \
  --protocol tcp \
  --port 443 \
  --source-group "$EKS_CLUSTER_SG" \
  --region "$REGION"

# 3. RDS Security Group (Public - NOT recommended for production)
echo -e "${YELLOW}Creating RDS Security Group (Public)...${NC}"
RDS_SG=$(aws ec2 create-security-group \
  --group-name "${CLUSTER_NAME}-rds-sg" \
  --description "Security group for RDS instance" \
  --vpc-id "$VPC_ID" \
  --region "$REGION" \
  --query 'GroupId' \
  --output text)

echo -e "${GREEN}✅ RDS SG: $RDS_SG${NC}"

# ⚠️ WARNING: This allows access from anywhere - NOT recommended for production
echo -e "${RED}⚠️ WARNING: Creating public access to RDS - NOT recommended for production${NC}"

# Allow PostgreSQL access from EKS nodes only
aws ec2 authorize-security-group-ingress \
  --group-id "$RDS_SG" \
  --protocol tcp \
  --port 5432 \
  --source-group "$EKS_NODE_SG" \
  --region "$REGION"

# Allow PostgreSQL access from your specific IP (for management)
# Replace with your actual IP address
YOUR_IP=$(curl -s ifconfig.me)
aws ec2 authorize-security-group-ingress \
  --group-id "$RDS_SG" \
  --protocol tcp \
  --port 5432 \
  --cidr "${YOUR_IP}/32" \
  --region "$REGION"

echo -e "${GREEN}✅ Allowed PostgreSQL access from your IP: ${YOUR_IP}${NC}"

# 4. ALB Security Group (if using Application Load Balancer)
echo -e "${YELLOW}Creating ALB Security Group...${NC}"
ALB_SG=$(aws ec2 create-security-group \
  --group-name "${CLUSTER_NAME}-alb-sg" \
  --description "Security group for Application Load Balancer" \
  --vpc-id "$VPC_ID" \
  --region "$REGION" \
  --query 'GroupId' \
  --output text)

echo -e "${GREEN}✅ ALB SG: $ALB_SG${NC}"

# Allow HTTP from anywhere
aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG" \
  --protocol tcp \
  --port 80 \
  --cidr "0.0.0.0/0" \
  --region "$REGION"

# Allow HTTPS from anywhere
aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG" \
  --protocol tcp \
  --port 443 \
  --cidr "0.0.0.0/0" \
  --region "$REGION"

# Allow ALB to communicate with EKS nodes
aws ec2 authorize-security-group-ingress \
  --group-id "$EKS_NODE_SG" \
  --protocol tcp \
  --port 8080 \
  --source-group "$ALB_SG" \
  --region "$REGION"

# Output summary
echo -e "${GREEN}🎉 Security Groups Created Successfully!${NC}"
echo -e "${YELLOW}Summary:${NC}"
echo -e "  EKS Cluster SG: $EKS_CLUSTER_SG"
echo -e "  EKS Node SG: $EKS_NODE_SG"
echo -e "  RDS SG: $RDS_SG"
echo -e "  ALB SG: $ALB_SG"
echo -e ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Update your EKS cluster to use these security groups"
echo -e "  2. Update your RDS instance to use the RDS security group"
echo -e "  3. Consider moving RDS to private subnets for production" 