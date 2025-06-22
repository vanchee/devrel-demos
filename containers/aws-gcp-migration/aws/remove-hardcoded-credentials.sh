#!/bin/bash

# Script to remove hardcoded credentials from files
# This script replaces hardcoded passwords with placeholders

set -e

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

echo -e "${BLUE}=== Removing Hardcoded Credentials ===${NC}"
echo "This script will replace hardcoded passwords with placeholders."
echo ""

# Create backup
print_status "Creating backup of current files..."
BACKUP_DIR="backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r aws/ "$BACKUP_DIR/"
cp -r gcp/ "$BACKUP_DIR/"
print_success "Backup created: $BACKUP_DIR"

# Files to update
FILES_TO_UPDATE=(
    "aws/setup-complete-infrastructure.sh"
    "aws/create-databases.sh"
    "aws/create-databases-data-api.sh"
    "aws/kubernetes/app-manifests/config.yaml"
    "aws/kubernetes/sql/populate-accounts-db.yaml"
    "aws/kubernetes/sql/populate-ledger-db.yaml"
    "aws/kubernetes/sql/accounts-testdata.sh"
    "aws/kubernetes/sql/ledger-testdata.sh"
    "aws/src/components/cloud-sql/accounts-db.yaml"
    "aws/src/components/cloud-sql/ledger-db.yaml"
    "gcp/kubernetes/config.yaml"
    "gcp/src/components/cloud-sql/accounts-db.yaml"
    "gcp/src/components/cloud-sql/ledger-db.yaml"
)

# Replace hardcoded passwords
print_status "Replacing hardcoded passwords..."

for file in "${FILES_TO_UPDATE[@]}"; do
    if [ -f "$file" ]; then
        print_status "Processing: $file"
        
        # Replace Chiapet22! with placeholder
        sed -i.bak 's/Chiapet22!/${DB_PASSWORD}/g' "$file"
        
        # Replace admin:admin with placeholders
        sed -i.bak 's/admin:admin/${DB_USERNAME}:${DB_PASSWORD}/g' "$file"
        sed -i.bak 's/POSTGRES_USER: admin/POSTGRES_USER: ${DB_USERNAME}/g' "$file"
        sed -i.bak 's/POSTGRES_PASSWORD: admin/POSTGRES_PASSWORD: ${DB_PASSWORD}/g' "$file"
        sed -i.bak 's/SPRING_DATASOURCE_USERNAME: admin/SPRING_DATASOURCE_USERNAME: ${DB_USERNAME}/g' "$file"
        sed -i.bak 's/SPRING_DATASOURCE_PASSWORD: admin/SPRING_DATASOURCE_PASSWORD: ${DB_PASSWORD}/g' "$file"
        
        # Remove .bak files
        rm -f "$file.bak"
        
        print_success "Updated: $file"
    else
        print_warning "File not found: $file"
    fi
done

# Create .env.example file
print_status "Creating .env.example file..."
cat > .env.example << EOF
# Database Configuration
# Copy this file to .env and set your actual values

# Database credentials
DB_USERNAME=postgres
DB_PASSWORD=your_secure_password_here

# RDS Configuration
RDS_ENDPOINT=your-rds-endpoint.ap-southeast-2.rds.amazonaws.com
REGION=ap-southeast-2

# Application Configuration
ACCOUNTS_DB=accounts-db
LEDGER_DB=ledger-db
EOF

print_success "Created: .env.example"

# Update .gitignore
print_status "Updating .gitignore..."
if ! grep -q ".env" .gitignore; then
    echo "" >> .gitignore
    echo "# Environment files" >> .gitignore
    echo ".env" >> .gitignore
    echo "*.env" >> .gitignore
    echo "secure-config.yaml" >> .gitignore
    echo "k8s-secret.yaml" >> .gitignore
    print_success "Updated: .gitignore"
fi

# Create secure deployment guide
print_status "Creating secure deployment guide..."
cat > SECURITY-GUIDE.md << EOF
# Security Guide - CymbalBank Migration

## 🔒 Credential Security

### ✅ What We Fixed:
- Removed hardcoded passwords from all files
- Replaced with environment variables and placeholders
- Created secure setup scripts
- Added .env.example template

### 🚨 Important Security Notes:

1. **Never commit real credentials to Git**
   - Use .env files (already added to .gitignore)
   - Use AWS Secrets Manager for production
   - Use Kubernetes secrets for containerized apps

2. **Use the secure setup script:**
   \`\`\`bash
   ./aws/secure-setup.sh
   \`\`\`

3. **For production deployments:**
   - Store credentials in AWS Secrets Manager
   - Use IAM roles for EKS pods
   - Enable encryption at rest and in transit
   - Use strong, unique passwords

4. **Environment variables:**
   - Copy .env.example to .env
   - Set your actual values in .env
   - Never commit .env files

### 🔧 Quick Setup:

1. **Set up environment:**
   \`\`\`bash
   cp .env.example .env
   # Edit .env with your actual values
   \`\`\`

2. **Use secure configuration:**
   \`\`\`bash
   ./aws/secure-setup.sh
   \`\`\`

3. **Deploy with secrets:**
   \`\`\`bash
   kubectl apply -f secure-config.yaml
   kubectl apply -f k8s-secret.yaml
   \`\`\`

### 📋 Files to Review:
- All files now use \${DB_USERNAME} and \${DB_PASSWORD} placeholders
- Check .env.example for required variables
- Review SECURITY-GUIDE.md for best practices
EOF

print_success "Created: SECURITY-GUIDE.md"

echo ""
print_success "🎉 Hardcoded credentials removed!"
echo ""
echo -e "${BLUE}Summary:${NC}"
echo "  ✅ Backup created: $BACKUP_DIR"
echo "  ✅ Hardcoded passwords replaced with placeholders"
echo "  ✅ .env.example created"
echo "  ✅ .gitignore updated"
echo "  ✅ SECURITY-GUIDE.md created"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review the changes in the files"
echo "  2. Set up your .env file with real credentials"
echo "  3. Use the secure setup script for deployment"
echo "  4. Consider using AWS Secrets Manager for production"
echo ""
echo -e "${RED}⚠️  Important:${NC}"
echo "  - Change any passwords that were exposed in Git history"
echo "  - Consider rotating database passwords"
echo "  - Review Git Guardian alerts after these changes" 