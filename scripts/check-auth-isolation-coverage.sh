#!/usr/bin/env bash
# Fails when a public async function in Sources/Auth has no call in AuthIsolationTests.swift.
#
# That file proves each public async Auth API compiles from a main-actor call site. The check
# matches by name only: a new overload, or a new function whose name the file already calls on
# another type, passes without a call, so add those calls by hand. It does not see async
# initializers or async properties.
set -euo pipefail

cd "$(dirname "$0")/.."

test_file=Tests/DefaultIsolationTests/AuthIsolationTests.swift
missing=$(
  find Sources/Auth -name '*.swift' -print0 \
    | xargs -0 perl -0777 -ne 'print "$1\n" while /\bpublic\s+(?:(?:static|mutating|nonisolated|final|override)\s+)*func\s+(\w+)[^{]*?\)\s*async\b/g' \
    | sort -u \
    | while read -r name; do
      grep -q "\.$name(" "$test_file" || echo "$name"
    done
)

if [ -n "$missing" ]; then
  echo "Public async Auth functions with no call in $test_file:" >&2
  echo "$missing" >&2
  exit 1
fi

echo "Every public async Auth function is called in $test_file."
