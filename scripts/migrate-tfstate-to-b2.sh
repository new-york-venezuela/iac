#!/bin/bash
# Migrate Terraform state from local to Backblaze B2 backend
# Usage: ./scripts/migrate-tfstate-to-b2.sh

set -e

echo "=== Terraform State Migration to B2 ==="
echo

# Check prerequisites
if [ ! -f ".env" ]; then
    echo "❌ .env not found. Copy from .env.example and fill in values."
    exit 1
fi

if [ ! -d "terraform" ]; then
    echo "❌ terraform/ directory not found. Run from repo root."
    exit 1
fi

# Source .env for B2 credentials
echo "📦 Loading B2 credentials from .env..."
source .env

# Verify B2 is enabled
if [ "$TF_VAR_b2_enabled" != "true" ]; then
    echo "❌ B2 not enabled. Set TF_VAR_b2_enabled='true' in .env"
    exit 1
fi

# Verify AWS credentials are set (needed for B2 backend)
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "❌ AWS credentials not set. Check .env has:"
    echo "   - B2_APPLICATION_KEY_ID"
    echo "   - B2_APPLICATION_KEY"
    echo "   - AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (auto-set from above)"
    exit 1
fi

cd terraform

# Determine bucket name
TFSTATE_BUCKET="${TF_VAR_b2_tfstate_bucket_name:-mailcow-tfstate-${TF_VAR_company_name}}"
echo "🪣  Target bucket: $TFSTATE_BUCKET"
echo

# Step 1: Check if local state exists
if [ ! -f "terraform.tfstate" ]; then
    echo "⚠️  No local state found. New deployment?"
    echo "   Running terraform init with new backend..."
    terraform init -backend-config="bucket=$TFSTATE_BUCKET"
    echo "✅ Backend initialized"
    exit 0
fi

echo "📋 Current state:"
terraform state list | head -5
echo "   ... ($(terraform state list | wc -l) resources total)"
echo

# Step 2: Backup local state before migration
BACKUP_FILE="terraform.tfstate.backup.$(date +%s)"
echo "💾 Backing up local state to $BACKUP_FILE..."
cp terraform.tfstate "$BACKUP_FILE"
echo "✅ Backup created"
echo

# Step 3: Initialize backend with migration
echo "🔄 Migrating state to B2..."
terraform init -migrate-state -backend-config="bucket=$TFSTATE_BUCKET"
echo

# Step 4: Verify migration
echo "✅ Verifying remote state..."
if terraform state list >/dev/null 2>&1; then
    RESOURCE_COUNT=$(terraform state list | wc -l)
    echo "✅ Remote state accessible ($RESOURCE_COUNT resources)"
else
    echo "❌ Failed to read remote state"
    echo "   Restoring local state..."
    rm -f terraform.tfstate terraform.tfstate.backup
    exit 1
fi

echo
echo "=== Migration Complete ==="
echo "Local backup: $BACKUP_FILE"
echo "Remote state: s3://$TFSTATE_BUCKET/terraform.tfstate"
echo
echo "🔐 Safe to delete local state:"
echo "   rm terraform.tfstate*"
echo
