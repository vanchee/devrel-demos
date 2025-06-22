# AWS Infrastructure Setup for CymbalBank Demo

This directory contains scripts to set up a complete AWS infrastructure for the CymbalBank demo application in the Sydney (ap-southeast-2) region.

## Architecture Overview

The setup creates a production-ready infrastructure with:

```
┌─────────────────────────────────────────────────────────────┐
│                    VPC: pv-syd-summit-demo-vpc             │
│                        (10.0.0.0/16)                       │
├─────────────────────────────────────────────────────────────┤
│  Public Subnets (AZ-A, AZ-B)                               │
│  ┌─────────────┐  ┌─────────────┐                          │
│  │   EKS       │  │   ALB       │                          │
│  │  Control    │  │  (Ingress)  │                          │
│  │  Plane      │  │             │                          │
│  └─────────────┘  └─────────────┘                          │
│                                                     │       │
│  Private Subnets (AZ-A, AZ-B)                      │       │
│  ┌─────────────┐  ┌─────────────┐                  │       │
│  │   EKS       │  │   EKS       │                  │       │
│  │   Nodes     │  │   Nodes     │                  │       │
│  │  (AZ-A)     │  │  (AZ-B)     │                  │       │
│  └─────────────┘  └─────────────┘                  │       │
│         │                 │                        │       │
│         └─────────┬───────┘                        │       │
│                   │                                │       │
│  Database Subnets (AZ-A, AZ-B)                     │       │
│  ┌─────────────┐  ┌─────────────┐                  │       │
│  │   RDS       │  │   RDS       │                  │       │
│  │  Primary    │  │  Read       │                  │       │
│  │  (AZ-A)     │  │  Replica    │                  │       │
│  └─────────────┘  └─────────────┘                  │       │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

Before running the setup script, ensure you have:

1. **AWS CLI** installed and configured
   ```bash
   aws configure
   ```

2. **kubectl** installed
   ```bash
   # macOS
   brew install kubectl
   
   # Ubuntu/Debian
   sudo apt-get install kubectl
   ```

3. **eksctl** installed
   ```bash
   # macOS
   brew install eksctl
   
   # Linux
   curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
   sudo mv /tmp/eksctl /usr/local/bin
   ```

4. **PostgreSQL client** (for database operations)
   ```bash
   # macOS
   brew install postgresql
   
   # Ubuntu/Debian
   sudo apt-get install postgresql-client
   ```

5. **Docker** installed (for building images)
   ```bash
   # macOS
   brew install docker
   
   # Ubuntu/Debian
   sudo apt-get install docker.io
   ```

6. **AWS Permissions** - Your AWS user/role needs permissions for:
   - EC2 (VPC, subnets, security groups, route tables)
   - EKS (clusters, node groups)
   - RDS (instances, subnet groups)
   - IAM (roles, policies)
   - ECR (repositories)

## Quick Start

### 1. Setup Infrastructure

```bash
# Make scripts executable
chmod +x setup-complete-infrastructure.sh
chmod +x cleanup-infrastructure.sh

# Run the setup script
./setup-complete-infrastructure.sh
```

This will create:
- VPC with proper subnets and routing
- EKS cluster with worker nodes
- RDS PostgreSQL instance
- All necessary security groups
- Database subnet group
- Required databases (`accounts-db`, `ledger-db`)

### 2. Deploy Application

After infrastructure is ready:

```bash
# Build and push Docker images
./ecr_build_push.sh

# Deploy Kubernetes resources
kubectl apply -f kubernetes/app-manifests/

# Populate databases with test data
kubectl apply -f kubernetes/sql/
```

### 3. Access Application

Get the ALB URL:
```bash
kubectl get ingress frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Default login credentials:
- Username: `testuser`
- Password: `bankofanthos`

## Infrastructure Details

### VPC Configuration
- **CIDR**: 10.0.0.0/16
- **Public Subnets**: 10.0.1.0/24, 10.0.2.0/24
- **Private Subnets**: 10.0.3.0/24, 10.0.4.0/24
- **Database Subnets**: 10.0.5.0/24, 10.0.6.0/24

### EKS Cluster
- **Name**: cymbalbank-cluster
- **Region**: ap-southeast-2 (Sydney)
- **Node Type**: t3.medium
- **Node Count**: 2 (min: 1, max: 4)
- **Kubernetes Version**: Latest supported by eksctl

### RDS Instance
- **Engine**: PostgreSQL 15.4
- **Instance Class**: db.t3.micro
- **Storage**: 20GB GP2
- **Multi-AZ**: No (for demo purposes)
- **Encryption**: Enabled
- **Backup Retention**: 7 days

### Security Groups

| Component | Inbound Rules | Purpose |
|-----------|---------------|---------|
| **EKS Control Plane** | 443 from EKS nodes | Cluster communication |
| **EKS Nodes** | 443 from control plane<br>All from same SG<br>8080 from ALB | Node communication |
| **RDS** | 5432 from EKS nodes<br>5432 from your IP | Database access |
| **ALB** | 80, 443 from 0.0.0.0/0 | Public access |

## Configuration Files

The setup script creates a `rds-config.yaml` file with the correct RDS endpoint for your Kubernetes ConfigMaps.

## Monitoring and Logging

### CloudWatch Logs
- EKS cluster logs are automatically sent to CloudWatch
- RDS logs can be enabled for monitoring

### VPC Flow Logs
Enable VPC Flow Logs for network monitoring:
```bash
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids $VPC_ID \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name "/aws/vpc/flowlogs" \
  --region ap-southeast-2
```

## Security Best Practices

### For Production Use

1. **Database Security**
   - Use AWS Secrets Manager for database credentials
   - Enable Multi-AZ deployment
   - Use larger instance types
   - Enable automated backups

2. **Network Security**
   - Consider using private subnets for RDS
   - Implement Network ACLs
   - Use AWS WAF for ALB protection

3. **Access Control**
   - Use IAM roles instead of access keys
   - Implement least privilege access
   - Enable CloudTrail for audit logging

4. **Monitoring**
   - Set up CloudWatch alarms
   - Enable VPC Flow Logs
   - Monitor RDS performance metrics

## Troubleshooting

### Common Issues

1. **EKS Cluster Creation Fails**
   - Check IAM permissions
   - Verify subnet configurations
   - Ensure sufficient IP addresses in subnets

2. **RDS Connection Issues**
   - Verify security group rules
   - Check subnet group configuration
   - Ensure RDS instance is in "Available" state

3. **Application Deployment Fails**
   - Check ECR repository access
   - Verify ConfigMap configurations
   - Check pod logs: `kubectl logs <pod-name>`

### Useful Commands

```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Check RDS status
aws rds describe-db-instances --db-instance-identifier pv-syd-summit-demo-rds

# Check security groups
aws ec2 describe-security-groups --filters "Name=group-name,Values=*cymbalbank*"

# Check VPC resources
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=pv-syd-summit-demo-vpc"
```

## Cleanup

To remove all infrastructure:

```bash
./cleanup-infrastructure.sh
```

**⚠️ Warning**: This will permanently delete all resources and data!

## Cost Estimation

Estimated monthly costs (Sydney region):
- EKS Cluster: ~$150-200
- RDS Instance (t3.micro): ~$25-30
- Data Transfer: ~$10-20
- **Total**: ~$185-250/month

## Support

For issues or questions:
1. Check AWS CloudTrail for API errors
2. Review CloudWatch logs
3. Verify IAM permissions
4. Check network connectivity

## Files in this Directory

- `setup-complete-infrastructure.sh` - Main setup script
- `cleanup-infrastructure.sh` - Cleanup script
- `ecr_build_push.sh` - Build and push Docker images
- `create-databases.sh` - Create databases in existing RDS
- `security-groups-example.sh` - Security group configuration example
- `README-INFRASTRUCTURE.md` - This file 