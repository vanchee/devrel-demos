#!/bin/bash

# Check available PostgreSQL versions in Sydney region

REGION="ap-southeast-2"

echo "Checking available PostgreSQL versions in $REGION..."

# Get all available PostgreSQL versions
echo "All available PostgreSQL versions:"
aws rds describe-db-engine-versions \
    --engine postgres \
    --region $REGION \
    --query 'DBEngineVersions[].EngineVersion' \
    --output table

echo ""
echo "Latest PostgreSQL version with encryption support:"
aws rds describe-db-engine-versions \
    --engine postgres \
    --region $REGION \
    --query 'DBEngineVersions[?SupportsStorageEncryption==`true`].EngineVersion' \
    --output text | tr '\t' '\n' | sort -V | tail -1

echo ""
echo "Recommended versions for production:"
aws rds describe-db-engine-versions \
    --engine postgres \
    --region $REGION \
    --query 'DBEngineVersions[?SupportsStorageEncryption==`true` && EngineVersion>=`14.0`].EngineVersion' \
    --output text | tr '\t' '\n' | sort -V 