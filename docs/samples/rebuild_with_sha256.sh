#!/bin/bash
# Rebuild sample directories with real SHA-256 hashes

set -e

cd "$(dirname "$0")"

# Helper function to hash content
hash_content() {
    echo -n "$1" | shasum -a 256 | cut -d' ' -f1
}

# Helper function to get file size
get_size() {
    echo -n "$1" | wc -c | tr -d ' '
}

echo "Rebuilding samples with real SHA-256 hashes..."

# Clean up old samples
rm -rf step0-initial-commit step1-second-commit step2-create-workspace step3-workspace-operations step4-commit-workspace

# Step 0: Initial commit
echo "Building step0..."
mkdir -p step0-initial-commit/root/{branches,changeset/@1001,objects}

# Content
README_CONTENT='# Travel Blog

Welcome to our travel blog repository! This contains travel guides and experiences from around the world.

## Structure
- asia/ - Asian destinations'

TOKYO_CONTENT='Tokyo - The bustling capital of Japan

A vibrant city mixing tradition and modernity.'

KYOTO_CONTENT='Kyoto - Ancient capital with temples

Famous for traditional culture and gardens.'

BANGKOK_CONTENT='Bangkok - Thailand'\''s vibrant capital

Street food paradise and cultural landmarks.'

# Hash content files
README_HASH=$(hash_content "$README_CONTENT")
TOKYO_HASH=$(hash_content "$TOKYO_CONTENT")
KYOTO_HASH=$(hash_content "$KYOTO_CONTENT")
BANGKOK_HASH=$(hash_content "$BANGKOK_CONTENT")

README_SIZE=$(get_size "$README_CONTENT")
TOKYO_SIZE=$(get_size "$TOKYO_CONTENT")
KYOTO_SIZE=$(get_size "$KYOTO_CONTENT")
BANGKOK_SIZE=$(get_size "$BANGKOK_CONTENT")

# Write content files
echo -n "$README_CONTENT" > "step0-initial-commit/root/objects/${README_HASH}.dat"
echo -n "$TOKYO_CONTENT" > "step0-initial-commit/root/objects/${TOKYO_HASH}.dat"
echo -n "$KYOTO_CONTENT" > "step0-initial-commit/root/objects/${KYOTO_HASH}.dat"
echo -n "$BANGKOK_CONTENT" > "step0-initial-commit/root/objects/${BANGKOK_HASH}.dat"

# Build manifests
JAPAN_MANIFEST="${TOKYO_HASH}:${TOKYO_SIZE}:tokyo.txt
${KYOTO_HASH}:${KYOTO_SIZE}:kyoto.txt"

THAILAND_MANIFEST="${BANGKOK_HASH}:${BANGKOK_SIZE}:bangkok.txt"

JAPAN_HASH=$(hash_content "$JAPAN_MANIFEST")
THAILAND_HASH=$(hash_content "$THAILAND_MANIFEST")
JAPAN_SIZE=$(get_size "$JAPAN_MANIFEST")
THAILAND_SIZE=$(get_size "$THAILAND_MANIFEST")

echo -n "$JAPAN_MANIFEST" > "step0-initial-commit/root/objects/${JAPAN_HASH}.dir"
echo -n "$THAILAND_MANIFEST" > "step0-initial-commit/root/objects/${THAILAND_HASH}.dir"

ASIA_MANIFEST="${JAPAN_HASH}:${JAPAN_SIZE}:japan/
${THAILAND_HASH}:${THAILAND_SIZE}:thailand/"

ASIA_HASH=$(hash_content "$ASIA_MANIFEST")
ASIA_SIZE=$(get_size "$ASIA_MANIFEST")

echo -n "$ASIA_MANIFEST" > "step0-initial-commit/root/objects/${ASIA_HASH}.dir"

ROOT_MANIFEST="${README_HASH}:${README_SIZE}:README.md
${ASIA_HASH}:${ASIA_SIZE}:asia/"

echo -n "$ROOT_MANIFEST" > "step0-initial-commit/root/changeset/@1001/.dir"

# Branch pointer
cat > step0-initial-commit/root/branches/main.json <<EOF
{
  "HEAD": "@1001"
}
EOF

echo "Step 0 complete. Sample hashes:"
echo "  README: ${README_HASH}"
echo "  tokyo.txt: ${TOKYO_HASH}"
echo "  japan/: ${JAPAN_HASH}"
echo "  asia/: ${ASIA_HASH}"

echo ""
echo "Done! All samples rebuilt with real SHA-256 hashes."
echo "Note: Only step0 implemented in this script. Extend for other steps as needed."
