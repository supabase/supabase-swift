#!/usr/bin/env bash
set -euo pipefail

warnings=$(xcodebuild clean docbuild \
  -scheme Supabase \
  -destination 'platform=macOS' \
  -quiet \
  2>&1 | grep -E "doesn't exist at |isn't a disambiguation for | is ambiguous at " | grep -v "SourcePackages/checkouts" | sed "s|$PWD|.|g" || true)

if [[ -n "$warnings" ]]; then
  echo "xcodebuild docbuild failed:"
  echo
  echo "$warnings"
  exit 1
fi
