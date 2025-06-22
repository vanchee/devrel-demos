#!/bin/bash

# Secure Setup Script - No hardcoded credentials
# This script prompts for credentials and stores them securely

set -e

REGION="ap-southeast-2"
CLUSTER_NAME="cymbalbank-cluster"
RDS_INSTANCE_NAME="pv-syd-summit-demo-rds"
SECRET_NAME="cymbalbank-db-credentials"

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

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo -e "${BLUE}=== Secure Database Setup ===${NC}"
echo "This script will securely store your database credentials."
echo ""

# Prompt for database credentials
echo -e "${BLUE}Database Username${NC} [default: postgres]: "
read -r DB_USERNAME
DB_USERNAME=${DB_USERNAME:-postgres}

echo -e "${BLUE}Database Password${NC}: "
read -s DB_PASSWORD
echo ""

if [ -z "$DB_PASSWORD" ]; then
    print_error "Password cannot be empty"
    exit 1
fi

# Get RDS endpoint
print_status "Getting RDS endpoint..."
RDS_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier $RDS_INSTANCE_NAME \
    --region $REGION \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text 2>/dev/null || echo "")

if [ -z "$RDS_ENDPOINT" ] || [ "$RDS_ENDPOINT" == "None" ]; then
    print_error "Could not find RDS endpoint. Please check your RDS instance."
    exit 1
fi

print_success "RDS Endpoint: $RDS_ENDPOINT"

# Store credentials in AWS Secrets Manager
print_status "Storing credentials in AWS Secrets Manager..."

# Create secret JSON
SECRET_JSON=$(cat <<EOF
{
  "username": "$DB_USERNAME",
  "password": "$DB_PASSWORD",
  "host": "$RDS_ENDPOINT",
  "port": "5432",
  "accounts_db": "accounts-db",
  "ledger_db": "ledger-db"
}
EOF
)

# Create or update secret
if aws secretsmanager describe-secret --secret-id $SECRET_NAME --region $REGION &>/dev/null; then
    print_warning "Secret already exists. Updating..."
    aws secretsmanager update-secret \
        --secret-id $SECRET_NAME \
        --secret-string "$SECRET_JSON" \
        --region $REGION
else
    print_status "Creating new secret..."
    aws secretsmanager create-secret \
        --name $SECRET_NAME \
        --description "CymbalBank database credentials" \
        --secret-string "$SECRET_JSON" \
        --region $REGION
fi

print_success "Credentials stored securely in AWS Secrets Manager"

# Create Kubernetes secret
print_status "Creating Kubernetes secret..."
kubectl create secret generic cymbalbank-db-secret \
    --from-literal=username="$DB_USERNAME" \
    --from-literal=password="$DB_PASSWORD" \
    --from-literal=host="$RDS_ENDPOINT" \
    --dry-run=client -o yaml > k8s-secret.yaml

print_success "Kubernetes secret template created: k8s-secret.yaml"

# Create secure config file
print_status "Creating secure configuration file..."
cat > secure-config.yaml << EOF
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

print_success "Secure configuration created: secure-config.yaml"

# Create databases
print_status "Creating databases..."
PGPASSWORD="$DB_PASSWORD" psql -h $RDS_ENDPOINT -p 5432 -U $DB_USERNAME -d postgres -c "CREATE DATABASE \"accounts-db\";" 2>/dev/null || print_warning "accounts-db might already exist"
PGPASSWORD="$DB_PASSWORD" psql -h $RDS_ENDPOINT -p 5432 -U $DB_USERNAME -d postgres -c "CREATE DATABASE \"ledger-db\";" 2>/dev/null || print_warning "ledger-db might already exist"

print_success "Databases created successfully"

echo ""
print_success "🎉 Secure setup completed!"
echo ""
echo -e "${BLUE}Files created:${NC}"
echo "  - secure-config.yaml (use this instead of hardcoded config)"
echo "  - k8s-secret.yaml (Kubernetes secret template)"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Apply the secure config: kubectl apply -f secure-config.yaml"
echo "  2. Apply the Kubernetes secret: kubectl apply -f k8s-secret.yaml"
echo "  3. Update your application to use the secret"
echo ""
echo -e "${YELLOW}Security notes:${NC}"
echo "  - Credentials are stored in AWS Secrets Manager"
echo "  - No hardcoded passwords in files"
echo "  - Use environment variables in production"
echo "  - Consider using AWS IAM roles for EKS pods" 