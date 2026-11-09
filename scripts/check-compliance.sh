#!/usr/bin/env bash
# Usage: check-compliance.sh [--update-baseline]
#
# Checks sdk-compliance.yaml against the public symbol graph. It fails when:
# - the manifest declares a symbol the public API no longer has (a stale entry), or
# - the undeclared public symbols differ from scripts/compliance-baseline.txt. A symbol missing
#   from the baseline is new public API: declare it. A baseline symbol that is no longer
#   undeclared means the baseline is out of date: run with --update-baseline and commit it.
#
# Only symbols declared under Sources/ count as undeclared, minus the files .sdk-parse-ignore
# matches, so dependency symbols in the graph do not count.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"

COMPLIANCE_FILE="sdk-compliance.yaml"
BASELINE_FILE="scripts/compliance-baseline.txt"

UPDATE_BASELINE=false
case "${1:-}" in
  "") ;;
  --update-baseline) UPDATE_BASELINE=true ;;
  *)
    echo "usage: $0 [--update-baseline]" >&2
    exit 2
    ;;
esac

TMP_DIR="$(mktemp -d)"
RESOLVED_FILE="Package.resolved"
# shellcheck disable=SC2329 # Called by the EXIT trap.
cleanup() {
  if [ -f "$TMP_DIR/Package.resolved" ]; then
    cp "$TMP_DIR/Package.resolved" "$RESOLVED_FILE"
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT
if [ -f "$RESOLVED_FILE" ]; then
  cp "$RESOLVED_FILE" "$TMP_DIR/Package.resolved"
fi

# Same flags as "macOS test flags" in DEVELOPMENT.md: without them the test
# targets fail to compile on macOS and most modules emit no symbol graph.
SWIFT_FLAGS=()
if [[ "$(uname)" == "Darwin" ]]; then
  SWIFT_FLAGS=(--triple "$(uname -m)-apple-macosx14.0" -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays)
fi

echo "Dumping public symbol graph..." >&2
DUMP_FAILED=false
find .build -name "*.symbols.json" -delete 2>/dev/null || true
# A failing exit here isn't necessarily fatal: test targets can fail to
# extract while library targets already landed first (same rationale as
# supabase/sdk's own extraction step).
if ! swift package ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} dump-symbol-graph --minimum-access-level public --skip-synthesized-members >/dev/null; then
  echo "⚠️  dump-symbol-graph exited non-zero; results below may be incomplete." >&2
  DUMP_FAILED=true
fi

SGFILES_LIST="$TMP_DIR/symbol-graphs"
find .build -name "*.symbols.json" > "$SGFILES_LIST"
if [ ! -s "$SGFILES_LIST" ]; then
  echo "error: no symbol graphs emitted" >&2
  exit 1
fi

# One line per public symbol: "<path>\t<name>", where <path> is the declaring file relative to the
# repository root (absolute for a dependency). A symbol the compiler synthesizes, such as a Codable
# init(from:), has no file: its path is "Sources/<module>/", with the module read from its mangled
# identifier ("s:4Auth…" is Auth).
#
# Kind identifiers that count as public API. Matches supabase/sdk's
# normalize-symbolgraph.ts KIND_MAP, plus swift.macro — which that map
# omits (a separate known gap, see SDK-1647) but which this repo's `@Table`
# family of attached macros needs in order to round-trip at all.
CODE_SYMBOLS="$TMP_DIR/code"
# shellcheck disable=SC2016 # $root and $p are jq variables.
xargs jq -r --arg root "$ROOT/" '
  .symbols[]
  | select(.kind.identifier as $k |
      ["swift.class","swift.struct","swift.enum","swift.protocol","swift.actor",
       "swift.func","swift.func.op","swift.method","swift.type.method","swift.init",
       "swift.subscript","swift.type.subscript","swift.property","swift.type.property",
       "swift.enum.case","swift.typealias","swift.associatedtype","swift.var","swift.macro"
      ] | index($k) != null)
  | .pathComponents as $p
  | .identifier.precise as $id
  | (if .location.uri then (.location.uri | ltrimstr("file://") | gsub("%20"; " ") | ltrimstr($root))
     else ([$id | capture("^s:(?<n>[0-9]+)") | .n]
       | if length == 1 then "Sources/" + $id[(2 + (.[0] | length)):(2 + (.[0] | length) + (.[0] | tonumber))] + "/" else "" end)
     end) + "\t"
    + (($p[:-1] + [($p[-1] | sub("\\(.*"; ""))]) | join("."))
' < "$SGFILES_LIST" | LC_ALL=C sort -u > "$CODE_SYMBOLS"

# Names swift package dump-symbol-graph can't see at all (currently just
# leading-underscore members, e.g. FunctionsClient._invokeWithStreamedResponse)
# are excluded from the manifest side too: they can never match, so leaving
# them in would always misreport as stale. Operators are quoted in the YAML
# (`- "=="`), so the quotes are stripped.
MANIFEST_SYMBOLS="$TMP_DIR/manifest"
grep -E '^[[:space:]]*-[[:space:]]+("[^"]+"|'"'"'[^'"'"']+'"'"'|[A-Za-z_])' "$COMPLIANCE_FILE" \
  | sed -E 's/^[[:space:]]*-[[:space:]]+//; s/[[:space:]]+#.*$//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' \
  | grep -vE '(^|\.)_[A-Za-z_]*$' \
  | LC_ALL=C sort -u > "$MANIFEST_SYMBOLS"

cut -f2 "$CODE_SYMBOLS" | LC_ALL=C sort -u > "$TMP_DIR/code-names"
STALE="$(comm -13 "$TMP_DIR/code-names" "$MANIFEST_SYMBOLS")"

# Files under Sources/, tracked or not, and those that supabase/sdk's check skips. git applies the
# same gitignore rules to .sdk-parse-ignore.
git ls-files -co --exclude-standard -- Sources > "$TMP_DIR/source-files"
git ls-files -cio --exclude-from=.sdk-parse-ignore -- Sources > "$TMP_DIR/ignored-files"

# Undeclared own-source symbols, as "<module>\t<name>". A synthesized symbol has no file, so it
# counts when its module has at least one file that is not ignored.
UNDECLARED="$TMP_DIR/undeclared"
awk -F'\t' '
  FILENAME == ARGV[1] { declared[$0] = 1; next }
  FILENAME == ARGV[2] { ignored[$0] = 1; next }
  FILENAME == ARGV[3] { if (!($0 in ignored)) { split($0, path, "/"); counted[path[2]] = 1 }; next }
  $1 !~ /^Sources\// || ($2 in declared) { next }
  {
    split($1, path, "/")
    if ($1 ~ /\/$/ ? (path[2] in counted) : !($1 in ignored)) print path[2] "\t" $2
  }
' "$MANIFEST_SYMBOLS" "$TMP_DIR/ignored-files" "$TMP_DIR/source-files" "$CODE_SYMBOLS" \
  | LC_ALL=C sort -u > "$UNDECLARED"

BASELINE="$TMP_DIR/baseline"
cp "$BASELINE_FILE" "$BASELINE" 2>/dev/null || : > "$BASELINE"

# The baseline only shrinks: an update drops the symbols that are now declared and never adds one.
if [ "$UPDATE_BASELINE" = true ]; then
  if [ "$DUMP_FAILED" = true ]; then
    echo "error: not updating $BASELINE_FILE from an incomplete symbol graph." >&2
    exit 1
  fi
  LC_ALL=C comm -12 "$UNDECLARED" "$BASELINE" > "$BASELINE_FILE"
  cp "$BASELINE_FILE" "$BASELINE"
  echo "Updated $BASELINE_FILE."
fi

status=0

if [ -n "$STALE" ]; then
  echo "❌ $COMPLIANCE_FILE declares symbols the public API no longer has:"
  while IFS= read -r symbol; do echo "  - $symbol"; done <<<"$STALE"
  echo
  echo "Remove them from sdk-compliance.yaml, or update the entry if the symbol moved or was renamed."
  echo
  status=1
fi

NEW="$(LC_ALL=C comm -23 "$UNDECLARED" "$BASELINE")"
FIXED="$(LC_ALL=C comm -13 "$UNDECLARED" "$BASELINE")"

if [ -n "$NEW" ]; then
  echo "❌ Public API not declared in $COMPLIANCE_FILE:"
  awk -F'\t' '{ print "  - " $1 ": " $2 }' <<<"$NEW"
  echo
  echo "Declare it in sdk-compliance.yaml."
  echo
  status=1
fi

if [ -n "$FIXED" ]; then
  echo "❌ $BASELINE_FILE lists symbols that are no longer undeclared:"
  awk -F'\t' '{ print "  - " $1 ": " $2 }' <<<"$FIXED"
  echo
  echo "Run ./scripts/check-compliance.sh --update-baseline and commit the result."
  echo
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "✅ sdk-compliance.yaml has no stale entries, and every undeclared symbol is in $BASELINE_FILE."
fi
exit "$status"
