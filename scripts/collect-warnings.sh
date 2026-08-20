#!/usr/bin/env bash
# Extracts compiler warnings from a raw xcodebuild / swift build log and writes them to
# stdout as `path<TAB>line<TAB>column<TAB>message` records, deduplicated.
#
# A single build reports the same warning once per target that compiles the file, so even
# one log needs deduplicating. scripts/annotate-warnings.sh does the same across logs.
#
# Warnings for files outside the repository (dependency checkouts, DerivedData) are
# dropped: GitHub cannot annotate a file that is not part of the checkout, and they are
# not actionable here anyway.
#
# Usage: scripts/collect-warnings.sh <log-file>
set -euo pipefail

LOG="${1?usage: collect-warnings.sh <log-file>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# xcbeautify colorizes its output, and warnings emitted by tools other than the compiler
# can carry escape sequences too, so strip them before matching.
sed -E $'s/\x1b\\[[0-9;]*[A-Za-z]//g' "$LOG" | awk -v root="$ROOT" '
  {
    sub(/^[[:space:]]+/, "")
  }
  match($0, /:[0-9]+:[0-9]+: warning: /) {
    path = substr($0, 1, RSTART - 1)
    if (index(path, root "/") != 1) next

    location = substr($0, RSTART + 1)
    split(location, parts, ":")
    message = substr($0, RSTART + RLENGTH)

    relative = substr(path, length(root) + 2)
    if (relative ~ /^\.build\// || relative ~ /^\.derivedData\//) next

    key = relative "\t" parts[1] "\t" parts[2] "\t" message
    if (!(key in seen)) {
      seen[key] = 1
      print key
    }
  }
'
