#!/bin/bash

# Update version script for semantic-release
# Usage: ./scripts/update-version.sh <new_version>

set -e

NEW_VERSION=$1

if [ -z "$NEW_VERSION" ]; then
    echo "Error: No version provided"
    echo "Usage: $0 <new_version>"
    exit 1
fi

echo "Updating version to $NEW_VERSION"

# Update Version.swift
sed -i.bak "s/private let _version = \"[^\"]*\"/private let _version = \"$NEW_VERSION\"/" Sources/Helpers/Version.swift

# Clean up backup file
rm -f Sources/Helpers/Version.swift.bak

echo "Version updated successfully to $NEW_VERSION"