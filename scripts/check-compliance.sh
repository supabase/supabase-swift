#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

COMPLIANCE_FILE="sdk-compliance.yaml"

RESOLVED_FILE="Package.resolved"
RESOLVED_BACKUP=""
if [ -f "$RESOLVED_FILE" ]; then
  RESOLVED_BACKUP="$(mktemp)"
  cp "$RESOLVED_FILE" "$RESOLVED_BACKUP"
  trap 'cp "$RESOLVED_BACKUP" "$RESOLVED_FILE"; rm -f "$RESOLVED_BACKUP"' EXIT
fi

# Same flags as "macOS test flags" in DEVELOPMENT.md: without them the test
# targets fail to compile on macOS and most modules emit no symbol graph.
SWIFT_FLAGS=()
if [[ "$(uname)" == "Darwin" ]]; then
  SWIFT_FLAGS=(--triple "$(uname -m)-apple-macosx14.0" -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays)
fi

echo "Dumping public symbol graph..." >&2
find .build -name "*.symbols.json" -delete 2>/dev/null || true
# A failing exit here isn't necessarily fatal: test targets can fail to
# extract while library targets already landed first (same rationale as
# supabase/sdk's own extraction step).
if ! swift package ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} dump-symbol-graph --minimum-access-level public --skip-synthesized-members >/dev/null; then
  echo "⚠️  dump-symbol-graph exited non-zero; results below may be incomplete." >&2
fi

SGFILES_LIST="$(mktemp)"
find .build -name "*.symbols.json" > "$SGFILES_LIST"
if [ ! -s "$SGFILES_LIST" ]; then
  echo "error: no symbol graphs emitted" >&2
  exit 1
fi

# Kind identifiers that count as public API. Matches supabase/sdk's
# normalize-symbolgraph.ts KIND_MAP, plus swift.macro — which that map
# omits (a separate known gap, see SDK-1647) but which this repo's `@Table`
# family of attached macros needs in order to round-trip at all.
CODE_SYMBOLS="$(mktemp)"
jq -s '[.[] | .symbols[]]' $(cat "$SGFILES_LIST") | jq -r '
  .[]
  | select(.kind.identifier as $k |
      ["swift.class","swift.struct","swift.enum","swift.protocol","swift.actor",
       "swift.func","swift.func.op","swift.method","swift.type.method","swift.init",
       "swift.subscript","swift.type.subscript","swift.property","swift.type.property",
       "swift.enum.case","swift.typealias","swift.associatedtype","swift.var","swift.macro"
      ] | index($k) != null)
  | .pathComponents as $p
  | ($p[:-1] + [($p[-1] | sub("\\(.*"; ""))]) | join(".")
' | LC_ALL=C sort -u > "$CODE_SYMBOLS"

# Names swift package dump-symbol-graph can't see at all (currently just
# leading-underscore members, e.g. FunctionsClient._invokeWithStreamedResponse)
# are excluded from the manifest side too: they can never match, so leaving
# them in would always misreport as stale.
MANIFEST_SYMBOLS="$(mktemp)"
grep -E '^[[:space:]]*-[[:space:]]+[A-Za-z_]' "$COMPLIANCE_FILE" \
  | sed -E 's/^[[:space:]]*-[[:space:]]+//' \
  | grep -vE '(^|\.)_[A-Za-z_]*$' \
  | LC_ALL=C sort -u > "$MANIFEST_SYMBOLS"

UNCOVERED="$(comm -23 "$CODE_SYMBOLS" "$MANIFEST_SYMBOLS")"
STALE="$(comm -13 "$CODE_SYMBOLS" "$MANIFEST_SYMBOLS")"

rm -f "$SGFILES_LIST" "$CODE_SYMBOLS" "$MANIFEST_SYMBOLS"

if [ -n "$UNCOVERED" ]; then
  echo "ℹ️  Public API not declared in $COMPLIANCE_FILE (pre-existing backlog, not fatal):"
  echo "$UNCOVERED" | sed 's/^/  - /'
  echo
fi

if [ -n "$STALE" ]; then
  echo "❌ $COMPLIANCE_FILE declares symbols the public API no longer has:"
  echo "$STALE" | sed 's/^/  - /'
  echo
  echo "Remove them from sdk-compliance.yaml, or update the entry if the symbol moved or was renamed."
  exit 1
fi

echo "✅ sdk-compliance.yaml has no stale entries."
