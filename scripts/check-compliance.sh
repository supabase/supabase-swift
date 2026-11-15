#!/usr/bin/env bash
# Usage: check-compliance.sh [--update-baseline]
#
# Checks sdk-compliance.yaml against the public symbol graph, @_spi symbols included. It fails when:
# - the manifest declares a symbol the public API no longer has (a stale entry), or
# - the undeclared public symbols differ from scripts/compliance-baseline.txt. A symbol missing
#   from the baseline is new public API: declare it. A baseline symbol that is no longer
#   undeclared means the baseline is out of date: run with --update-baseline and commit it.
#
# An @_spi symbol counts only for the stale check: declaring one is optional, so the baseline
# never holds one, but a declared one that disappears fails like any other stale entry.
#
# Only symbols declared under Sources/ count as undeclared, minus the files .sdk-parse-ignore
# matches, so dependency symbols in the graph do not count.
set -euo pipefail

# comm needs its input sorted in the collation it compares with. One locale for every sort and
# comm: a UTF-8 locale on a CI runner otherwise reports false stale entries.
export LC_ALL=C

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
find .build -name "*.symbols.json" -delete 2>/dev/null || true
# A failing exit here isn't necessarily fatal: test targets can fail to
# extract while library targets already landed first (same rationale as
# supabase/sdk's own extraction step). The module check below catches a
# library target that did not land.
if ! swift package ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} dump-symbol-graph --minimum-access-level public --skip-synthesized-members --include-spi-symbols >/dev/null; then
  echo "⚠️  dump-symbol-graph exited non-zero; checking that every SDK module emitted a graph." >&2
fi

SGFILES_LIST="$TMP_DIR/symbol-graphs"
find .build -name "*.symbols.json" > "$SGFILES_LIST"

# Files under Sources/, tracked or not, and those that supabase/sdk's check skips. git applies the
# same gitignore rules to .sdk-parse-ignore. A module is a Sources/ directory with at least one
# file that is not ignored, and each one must have emitted a symbol graph.
git ls-files -co --exclude-standard -- Sources > "$TMP_DIR/source-files"
git ls-files -cio --exclude-from=.sdk-parse-ignore -- Sources > "$TMP_DIR/ignored-files"
grep -vxF -f "$TMP_DIR/ignored-files" "$TMP_DIR/source-files" > "$TMP_DIR/counted-files" || true
MODULES="$(cut -d/ -f2 "$TMP_DIR/counted-files" | sort -u)"
MISSING="$(
  for module in $MODULES; do
    grep -q "/$module\.symbols\.json$" "$SGFILES_LIST" || echo "  - $module"
  done
)"
if [ -n "$MISSING" ]; then
  echo "error: no symbol graph emitted for these modules:" >&2
  echo "$MISSING" >&2
  exit 1
fi

# One line per public symbol: "<path>\t<name>\t<spi>", where <spi> is 1 for an @_spi symbol and
# <path> is the declaring file relative to the repository root (absolute for a dependency). A symbol the compiler synthesizes, such as a Codable
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
    + (($p[:-1] + [($p[-1] | sub("\\(.*"; ""))]) | join(".")) + "\t"
    + (if .spi then "1" else "0" end)
' < "$SGFILES_LIST" | sort -u > "$CODE_SYMBOLS"

# Swift 6.4's default build system ignores --include-spi-symbols and gives no warning. Without
# this guard every declared @_spi symbol would look stale.
# Only a declaration counts: not an @_spi import, a doc comment, or a DocC article.
if ! grep -q $'\t1$' "$CODE_SYMBOLS"; then
  { grep '\.swift$' "$TMP_DIR/counted-files" || true; } | tr '\n' '\0' \
    | { xargs -0 grep -hE '^[[:space:]]*@_spi\(' || true; } > "$TMP_DIR/spi-attributes"
  if grep -qv 'import ' "$TMP_DIR/spi-attributes"; then
    echo "error: Sources/ declares @_spi symbols, but the symbol graph has none." >&2
    echo "This toolchain drops --include-spi-symbols. Put a Swift 6.3 toolchain (Xcode 26) first" >&2
    echo "on PATH and run it again." >&2
    exit 1
  fi
fi

# Names swift package dump-symbol-graph can't see at all (currently just
# leading-underscore members, e.g. FunctionsClient._invokeWithStreamedResponse)
# are excluded from the manifest side too: they can never match, so leaving
# them in would always misreport as stale. Operators are quoted in the YAML
# (`- "=="`), so the quotes are stripped.
MANIFEST_SYMBOLS="$TMP_DIR/manifest"
grep -E '^[[:space:]]*-[[:space:]]+("[^"]+"|'"'"'[^'"'"']+'"'"'|[A-Za-z_])' "$COMPLIANCE_FILE" \
  | sed -E 's/^[[:space:]]*-[[:space:]]+//; s/[[:space:]]+#.*$//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' \
  | grep -vE '(^|\.)_[A-Za-z_]*$' \
  | sort -u > "$MANIFEST_SYMBOLS"

cut -f2 "$CODE_SYMBOLS" | sort -u > "$TMP_DIR/code-names"
STALE="$(comm -13 "$TMP_DIR/code-names" "$MANIFEST_SYMBOLS")"

# Undeclared own-source symbols, as "<module>\t<name>". A synthesized symbol has no file, so it
# counts when its module is one of $MODULES.
UNDECLARED="$TMP_DIR/undeclared"
awk -F'\t' -v modules="${MODULES//$'\n'/ }" '
  BEGIN { n = split(modules, list, " "); for (i = 1; i <= n; i++) counted[list[i]] = 1 }
  FILENAME == ARGV[1] { declared[$0] = 1; next }
  FILENAME == ARGV[2] { ignored[$0] = 1; next }
  $1 !~ /^Sources\// || $3 == "1" || ($2 in declared) { next }
  {
    split($1, path, "/")
    if ($1 ~ /\/$/ ? (path[2] in counted) : !($1 in ignored)) print path[2] "\t" $2
  }
' "$MANIFEST_SYMBOLS" "$TMP_DIR/ignored-files" "$CODE_SYMBOLS" | sort -u > "$UNDECLARED"

BASELINE="$TMP_DIR/baseline"
cp "$BASELINE_FILE" "$BASELINE" 2>/dev/null || : > "$BASELINE"

# The baseline only shrinks: an update drops the symbols that are now declared and never adds one.
if [ "$UPDATE_BASELINE" = true ]; then
  comm -12 "$UNDECLARED" "$BASELINE" > "$BASELINE_FILE"
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

NEW="$(comm -23 "$UNDECLARED" "$BASELINE")"
FIXED="$(comm -13 "$UNDECLARED" "$BASELINE")"

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
