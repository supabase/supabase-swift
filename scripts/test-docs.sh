#!/usr/bin/env bash
set -euo pipefail

warnings=$(xcodebuild clean docbuild \
  -scheme Supabase \
  -destination 'platform=macOS' \
  -quiet \
  2>&1 | grep "couldn't be resolved to known documentation" | sed "s|$PWD|.|g" || true)

if [[ -n "$warnings" ]]; then
  echo "xcodebuild docbuild failed:"
  echo
  echo "$warnings"
  exit 1
fi
