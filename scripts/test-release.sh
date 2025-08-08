#!/bin/bash

# Test script for release workflow without actually releasing
# Usage: ./scripts/test-release.sh

set -e

echo "🧪 Testing release workflow components..."

# Check if we're in the right directory
if [ ! -f "package.json" ] || [ ! -f ".releaserc.json" ]; then
    echo "❌ Error: Must run from project root directory"
    exit 1
fi

# Check if Node.js is available
if ! command -v node &> /dev/null; then
    echo "❌ Error: Node.js is required but not installed"
    exit 1
fi

# Check if npm is available
if ! command -v npm &> /dev/null; then
    echo "❌ Error: npm is required but not installed"
    exit 1
fi

echo "✅ Node.js and npm are available"

# Install dependencies
echo "📦 Installing dependencies..."
npm ci

echo "✅ Dependencies installed"

# Test semantic-release dry-run
echo "🔍 Testing semantic-release dry-run..."
npx semantic-release --dry-run

echo "✅ Semantic-release dry-run completed"

# Test version update script
echo "🔧 Testing version update script..."
./scripts/update-version.sh 9.9.9-test

# Verify the change
if grep -q "private let _version = \"9.9.9-test\"" Sources/Helpers/Version.swift; then
    echo "✅ Version update script works correctly"
else
    echo "❌ Version update script failed"
    exit 1
fi

# Revert the change
git checkout -- Sources/Helpers/Version.swift
echo "✅ Version change reverted"

# Test workflow configuration
echo "📋 Testing workflow configuration..."

# Check if required files exist
required_files=(
    ".github/workflows/release.yml"
    ".releaserc.json"
    "package.json"
    "scripts/update-version.sh"
    "Sources/Helpers/Version.swift"
)

for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file exists"
    else
        echo "❌ $file missing"
        exit 1
    fi
done

# Check semantic-release configuration
if npx semantic-release --dry-run --help &> /dev/null; then
    echo "✅ Semantic-release is properly configured"
else
    echo "❌ Semantic-release configuration error"
    exit 1
fi

echo ""
echo "🎉 All tests passed! The release workflow should work correctly."
echo ""
echo "To test the actual workflow:"
echo "1. Push this branch to GitHub"
echo "2. Create a PR to main with conventional commit messages"
echo "3. The release-test workflow will run automatically"
echo "4. Check the workflow logs for any issues"
