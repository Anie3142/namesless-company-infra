#!/bin/bash

# Cleanup Script for S3 Buckets with Versioning
# This script deletes all versions and then removes the buckets

set -e

echo "🧹 S3 Bucket Cleanup Script"
echo "=========================="
echo ""

# List of buckets to clean (update suffix if different)
BUCKETS=(
  "kops-state-46422bfa"
  "terraform-state-kops-46422bfa"
  "kops-infra-oidc-dev-k8s-local"
)

for BUCKET in "${BUCKETS[@]}"; do
  echo "Processing bucket: $BUCKET"
  
  # Check if bucket exists
  if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "  ✓ Bucket exists"
    
    # Delete all versions
    echo "  → Deleting all object versions..."
    aws s3api list-object-versions --bucket "$BUCKET" \
      --query 'Versions[].{Key:Key,VersionId:VersionId}' \
      --output text | while read key version; do
      if [ -n "$key" ] && [ -n "$version" ]; then
        aws s3api delete-object --bucket "$BUCKET" --key "$key" --version-id "$version" > /dev/null 2>&1
      fi
    done
    
    # Delete all delete markers
    echo "  → Deleting delete markers..."
    aws s3api list-object-versions --bucket "$BUCKET" \
      --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
      --output text | while read key version; do
      if [ -n "$key" ] && [ -n "$version" ]; then
        aws s3api delete-object --bucket "$BUCKET" --key "$key" --version-id "$version" > /dev/null 2>&1
      fi
    done
    
    # Delete the bucket
    echo "  → Deleting bucket..."
    aws s3 rb "s3://$BUCKET" --force
    
    echo "  ✓ Bucket $BUCKET deleted"
  else
    echo "  ⊘ Bucket doesn't exist (already deleted)"
  fi
  
  echo ""
done

echo "✅ All buckets cleaned up!"
echo ""
echo "Note: Run this command to verify:"
echo "  aws s3 ls | grep -E '(kops-state|terraform-state|kops-infra-oidc)'"
