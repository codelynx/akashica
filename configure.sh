#!/bin/bash
# configure.sh - Setup credentials template for S3 tests

CREDENTIALS_DIR=".credentials"
CREDENTIALS_FILE="$CREDENTIALS_DIR/aws-credentials.json"

# Check for --force flag
if [ "$1" = "--force" ]; then
    FORCE=true
else
    FORCE=false
fi

# Skip if exists (unless --force)
if [ -f "$CREDENTIALS_FILE" ] && [ "$FORCE" = false ]; then
    echo "✓ $CREDENTIALS_FILE already exists (use --force to overwrite)"
    exit 0
fi

# Create directory and template
mkdir -p "$CREDENTIALS_DIR"

cat > "$CREDENTIALS_FILE" << 'EOF'
{
  "accessKeyId": "YOUR_AWS_ACCESS_KEY_ID",
  "secretAccessKey": "YOUR_AWS_SECRET_ACCESS_KEY",
  "region": "us-east-1",
  "bucket": "your-test-bucket-name"
}
EOF

echo "✓ Created $CREDENTIALS_FILE"
echo "  Edit this file with your AWS credentials to enable S3 tests"
