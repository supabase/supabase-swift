#!/usr/bin/env bash
# Usage: [GENERATE_ARGS="..."] [CHECK_ARGS="..."] api-docs.sh [--check | --preview <docs-checkout>]
#
# Generates the API docs definitions in docs/api-docs/definitions from the doc comments of
# the public API, one for each public function, method and initializer, documented or not, and
# checks them against the schema of supabase.com/docs. With --check, it only checks the
# definitions that are there.
#
# Two environment variables hand options on to the two tools, the same two in every SDK. The
# options are separated by spaces. Every run that uses the tool takes them:
#   GENERATE_ARGS  options of doc-generator:  GENERATE_ARGS="--verbose" api-docs.sh
#   CHECK_ARGS     options of doc-check:      CHECK_ARGS="--schema-url <url>" api-docs.sh --check
#
# The check uses the schema bundled with it. The options of doc-check choose another one:
# --schema-url <url>, or --schema-git <repository> --schema-ref <ref> --schema-path <path>.
#
# With --preview, it generates and checks as usual, and then copies the definitions into a local
# checkout of supabase/supabase, on a branch that has the new reference pages. Then it starts the
# docs site there (pnpm dev:docs), unless it already runs, and opens the page in a browser.
#
# The generator and the check live in supabase/sdk and are shared by every SDK. This script only
# builds their input: the symbol graphs of the package. See tools/api-docs/README.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TOOLS="$ROOT/tools/api-docs"
OUT="$ROOT/.build/api-docs"

usage() {
  echo "usage: [GENERATE_ARGS=\"...\"] [CHECK_ARGS=\"...\"] $0 [--check | --preview <docs-checkout>]" >&2
  exit 2
}

CHECK_ONLY=false
PREVIEW_DIR=""
case "${1:-}" in
  "") ;;
  --check)
    [ $# -eq 1 ] || usage
    CHECK_ONLY=true
    ;;
  --preview)
    [ $# -eq 2 ] || usage
    # npm runs the tools from tools/api-docs, where a relative path would point somewhere else.
    if ! PREVIEW_DIR="$(cd "$2" 2>/dev/null && pwd -P)"; then
      echo "error: $2 is not a directory." >&2
      exit 1
    fi
    ;;
  *) usage ;;
esac

if [ ! -d "$TOOLS/node_modules" ]; then
  echo "tools/api-docs is not set up. Follow \"Setup\" in tools/api-docs/README.md, then retry." >&2
  exit 1
fi

# The options for the two tools, split at whitespace. A wildcard in them is not expanded.
GENERATE_OPTIONS=()
CHECK_OPTIONS=()
IFS=$' \t\n' read -r -d '' -a GENERATE_OPTIONS <<< "${GENERATE_ARGS:-}" || true
IFS=$' \t\n' read -r -d '' -a CHECK_OPTIONS <<< "${CHECK_ARGS:-}" || true

# The bash of macOS, 3.2, takes "${list[@]}" of an empty list for an unset variable under `set -u`.
generate() {
  npm --prefix "$TOOLS" run --silent generate -- ${GENERATE_OPTIONS[@]+"${GENERATE_OPTIONS[@]}"}
}
check() {
  npm --prefix "$TOOLS" run --silent check -- ${CHECK_OPTIONS[@]+"${CHECK_OPTIONS[@]}"}
}

if [ "$CHECK_ONLY" = true ]; then
  check
  exit
fi

# A symbol graph holds what one platform compiles. A Linux build has no code behind
# canImport(AuthenticationServices), so the definitions always come from a macOS build.
if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: the API docs definitions are generated on macOS." >&2
  exit 1
fi

# A build can rewrite Package.resolved. Same guard as check-compliance.sh.
TMP_DIR="$(mktemp -d)"
RESOLVED_FILE="$ROOT/Package.resolved"
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

echo "Emitting symbol graphs..." >&2
mkdir -p "$OUT/symbol-graphs"
# The compiler writes the graphs, not `swift package dump-symbol-graph`: on Swift 6.4 that
# command drops every @_spi symbol (see check-compliance.sh).
#
# The build has a scratch path of its own. Its flags differ from those of a normal build, so
# sharing .build would turn every switch between the two into a full rebuild.
#
# The graphs of an earlier run stay in place: the compiler rewrites a module's graph when it
# compiles the module again, and a module it does not compile again has not changed.
swift build \
  --package-path "$ROOT" \
  --scratch-path "$OUT/build" \
  --target Supabase \
  --triple "$(uname -m)-apple-macosx14.0" \
  -Xswiftc -emit-symbol-graph \
  -Xswiftc -emit-symbol-graph-dir -Xswiftc "$OUT/symbol-graphs" \
  -Xswiftc -symbol-graph-minimum-access-level -Xswiftc public \
  -Xswiftc -include-spi-symbols >&2

generate
check

if [ -n "$PREVIEW_DIR" ]; then
  npm --prefix "$TOOLS" run --silent preview -- "$PREVIEW_DIR"
fi
