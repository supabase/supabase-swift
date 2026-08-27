#!/usr/bin/env bash
# Checks sdk-compliance.yaml against the package's current public API.
#
# Reproduces, locally and without a base ref, the part of supabase/sdk's
# capability-matrix gate (validate-sdk-compliance-swift.yml) that CI only
# catches remotely: it dumps the current public symbol graph, normalizes it
# the same way upstream's normalize-symbolgraph.ts does (pathComponents
# joined with ".", everything from the first "(" in the last component
# stripped), and does a comm-style diff against every symbol
# sdk-compliance.yaml declares (`symbols` + `supporting_symbols`, top level
# and per feature).
#
# This only fails the build on STALE entries: symbols the manifest still
# declares after the code that implemented them was deleted, moved, or
# renamed. That's the exact failure mode from SDK-1624/SDK-1643 — 15 symbols
# were dropped across 43 commits and nothing local caught that the manifest
# still listed them, because the remote gate only ever reports on *new*
# symbols.
#
# Symbols present in code but missing from the manifest are reported too,
# but are advisory only here, not fatal: the manifest carries a large
# backlog of pre-existing supporting types (structs, DTO properties, etc.)
# it never enumerated, predating this script, and upstream's CI already
# gates genuinely new public API against the matrix on every PR diff.
# Making that backlog fatal here would fail on a clean main and train
# whoever runs this to ignore or disable it. Register new public API in
# sdk-compliance.yaml as you add it — see AGENTS.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

COMPLIANCE_FILE="sdk-compliance.yaml"

# dump-symbol-graph re-resolves the package graph as a side effect and
# rewrites Package.resolved. Back it up and restore it so this check doesn't
# leave unrelated churn behind.
RESOLVED_FILE="Package.resolved"
RESOLVED_BACKUP=""
if [ -f "$RESOLVED_FILE" ]; then
  RESOLVED_BACKUP="$(mktemp)"
  cp "$RESOLVED_FILE" "$RESOLVED_BACKUP"
  trap 'cp "$RESOLVED_BACKUP" "$RESOLVED_FILE"; rm -f "$RESOLVED_BACKUP"' EXIT
fi

echo "Dumping public symbol graph..." >&2
# || true: test targets may fail to extract; library targets land first
# (same rationale as supabase/sdk's own extraction step).
swift package dump-symbol-graph --minimum-access-level public --skip-synthesized-members >/dev/null || true

SGFILES_LIST="$(mktemp)"
find .build -maxdepth 4 -name "*.symbols.json" > "$SGFILES_LIST"
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

# sdk-compliance.yaml only ever holds plain "- Symbol.Name" list items under
# `symbols:`/`supporting_symbols:` (top level or per feature) — there's no
# other array in the schema — so grepping for list items is a safe
# substitute for a real YAML parser here.
#
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
