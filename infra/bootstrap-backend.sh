#!/bin/bash
# Bootstrap Terraform S3 backend and DynamoDB lock table
# Run this ONCE before running terraform init

set -euo pipefail

BUCKET_NAME="${1:-terraform-state-$(date +%s)}"
DYNAMODB_TABLE="terraform-locks"
REGION="eu-west-1"

echo "Creating Terraform backend resources..."
echo "   S3 Bucket: $BUCKET_NAME"
echo "   Region: $REGION"
echo "   DynamoDB Table: $DYNAMODB_TABLE"

# Create S3 bucket
echo "── Creating S3 bucket ──"
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" \
  || { echo "Error: Bucket may already exist"; exit 1; }

# Enable versioning
echo "── Enabling S3 versioning ──"
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# Enable encryption
echo "── Enabling S3 encryption ──"
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
echo "── Blocking public access ──"
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Create DynamoDB table
echo "── Creating DynamoDB lock table ──"
aws dynamodb create-table \
  --table-name "$DYNAMODB_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" \
  || { echo "Error: Table may already exist"; exit 1; }

# Wait for table to be active
echo "── Waiting for DynamoDB table ──"
aws dynamodb wait table-exists \
  --table-name "$DYNAMODB_TABLE" \
  --region "$REGION"

echo ""
echo "Backend ready!"
echo ""
echo "Add this to infra/backend.tf:"
echo ""
cat << EOF
terraform {
  backend "s3" {
    bucket         = "$BUCKET_NAME"
    key            = "eks/terraform.tfstate"
    region         = "$REGION"
    dynamodb_table = "$DYNAMODB_TABLE"
    encrypt        = true
  }
}
EOF
