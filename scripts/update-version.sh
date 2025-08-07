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

# Validate version format (semantic versioning)
if ! [[ $NEW_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?(\+[a-zA-Z0-9.-]+)?$ ]]; then
    echo "Error: Invalid version format. Expected semantic version (e.g., 1.0.0, 1.0.0-beta.1)"
    exit 1
fi

echo "Updating version to $NEW_VERSION"

# Check if Version.swift exists
if [ ! -f "Sources/Helpers/Version.swift" ]; then
    echo "Error: Sources/Helpers/Version.swift not found"
    exit 1
fi

# Update Version.swift
sed -i.bak "s/private let _version = \"[^\"]*\"/private let _version = \"$NEW_VERSION\"/" Sources/Helpers/Version.swift

# Verify the change was made
if ! grep -q "private let _version = \"$NEW_VERSION\"" Sources/Helpers/Version.swift; then
    echo "Error: Failed to update version in Sources/Helpers/Version.swift"
    # Restore backup
    mv Sources/Helpers/Version.swift.bak Sources/Helpers/Version.swift
    exit 1
fi

# Clean up backup file
rm -f Sources/Helpers/Version.swift.bak

echo "Version updated successfully to $NEW_VERSION"