#!/bin/bash

# AWS RDS Data API Database Creation Script
# This method works if your RDS instance has Data API enabled

set -e

# Configuration
REGION="ap-southeast-2"
RDS_INSTANCE_ID="pv-rds-gcpdemo-summit"  # Replace with your actual RDS instance name
DB_USERNAME="postgres"
DB_PASSWORD=""  # Replace with your actual password

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔍 Getting RDS instance details...${NC}"

# Get RDS cluster ARN (for Aurora) or instance ARN
RDS_ARN=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_INSTANCE_ID" \
  --region "$REGION" \
  --query 'DBInstances[0].DBInstanceArn' \
  --output text)

if [ -z "$RDS_ARN" ] || [ "$RDS_ARN" == "None" ]; then
    echo -e "${RED}❌ Could not get RDS ARN. Please check your instance name and region.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ RDS ARN: $RDS_ARN${NC}"

# Check if Data API is enabled
echo -e "${YELLOW}🔍 Checking if Data API is enabled...${NC}"

# Note: Data API is typically available for Aurora Serverless, not regular RDS PostgreSQL
# This is included for completeness but may not work with your setup

# Create databases using Data API
echo -e "${YELLOW}🗄️ Creating databases using Data API...${NC}"

# Create accounts-db
echo -e "${YELLOW}Creating accounts-db...${NC}"
aws rds-data execute-statement \
  --resource-arn "$RDS_ARN" \
  --secret-arn "your-secret-arn" \
  --sql "CREATE DATABASE \"accounts-db\";" \
  --region "$REGION" || echo -e "${YELLOW}⚠️ accounts-db might already exist or Data API not available${NC}"

# Create ledger-db
echo -e "${YELLOW}Creating ledger-db...${NC}"
aws rds-data execute-statement \
  --resource-arn "$RDS_ARN" \
  --secret-arn "your-secret-arn" \
  --sql "CREATE DATABASE \"ledger-db\";" \
  --region "$REGION" || echo -e "${YELLOW}⚠️ ledger-db might already exist or Data API not available${NC}"

echo -e "${GREEN}🎉 Database creation attempted!${NC}"
echo -e "${YELLOW}Note: Data API may not be available for your RDS instance.${NC}"
echo -e "${YELLOW}Use the create-databases.sh script instead for regular RDS PostgreSQL.${NC}" 
