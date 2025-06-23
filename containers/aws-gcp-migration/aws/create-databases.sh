#!/bin/bash

# AWS RDS Database Creation Script
# This script creates the required databases in an existing RDS PostgreSQL instance

set -e

# Configuration
REGION="ap-southeast-2"
RDS_INSTANCE_ID="your-rds-instance-name"  # Replace with your actual RDS instance name
DB_USERNAME="postgres"
DB_PASSWORD=""  # Replace with your actual password

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔍 Getting RDS instance details...${NC}"

# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_INSTANCE_ID" \
  --region "$REGION" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

if [ -z "$RDS_ENDPOINT" ] || [ "$RDS_ENDPOINT" == "None" ]; then
    echo -e "${RED}❌ Could not get RDS endpoint. Please check your instance name and region.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ RDS Endpoint: $RDS_ENDPOINT${NC}"

# Check if PostgreSQL client is installed
if ! command -v psql &> /dev/null; then
    echo -e "${RED}❌ PostgreSQL client (psql) is not installed.${NC}"
    echo "Please install it:"
    echo "  Ubuntu/Debian: sudo apt-get install postgresql-client"
    echo "  macOS: brew install postgresql"
    echo "  CentOS/RHEL: sudo yum install postgresql"
    exit 1
fi

echo -e "${YELLOW}🔍 Testing connection to RDS instance...${NC}"

# Test connection
if ! PGPASSWORD="$DB_PASSWORD" psql -h "$RDS_ENDPOINT" -p 5432 -U "$DB_USERNAME" -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${RED}❌ Cannot connect to RDS instance. Please check:${NC}"
    echo "  - RDS instance is running"
    echo "  - Security groups allow connections from your IP"
    echo "  - Username and password are correct"
    echo "  - VPC/subnet configuration"
    exit 1
fi

echo -e "${GREEN}✅ Successfully connected to RDS instance${NC}"

# Create databases
echo -e "${YELLOW}🗄️ Creating databases...${NC}"

# Create accounts-db
echo -e "${YELLOW}Creating accounts-db...${NC}"
if PGPASSWORD="$DB_PASSWORD" psql -h "$RDS_ENDPOINT" -p 5432 -U "$DB_USERNAME" -d postgres -c "CREATE DATABASE \"accounts-db\";" 2>/dev/null; then
    echo -e "${GREEN}✅ Created accounts-db${NC}"
else
    echo -e "${YELLOW}⚠️ accounts-db might already exist (this is OK)${NC}"
fi

# Create ledger-db
echo -e "${YELLOW}Creating ledger-db...${NC}"
if PGPASSWORD="$DB_PASSWORD" psql -h "$RDS_ENDPOINT" -p 5432 -U "$DB_USERNAME" -d postgres -c "CREATE DATABASE \"ledger-db\";" 2>/dev/null; then
    echo -e "${GREEN}✅ Created ledger-db${NC}"
else
    echo -e "${YELLOW}⚠️ ledger-db might already exist (this is OK)${NC}"
fi

# Verify databases were created
echo -e "${YELLOW}🔍 Verifying databases...${NC}"
PGPASSWORD="$DB_PASSWORD" psql -h "$RDS_ENDPOINT" -p 5432 -U "$DB_USERNAME" -d postgres -c "\l" | grep -E "(accounts-db|ledger-db)"

echo -e "${GREEN}🎉 Database creation completed!${NC}"
echo -e "${GREEN}You can now run the Kubernetes deployment scripts.${NC}" 
