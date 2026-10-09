#!/usr/bin/env bash
# Fails if building the `PostgREST` target compiles any part of swift-syntax.
#
# The macros live in `PostgrestMacros`, a separate product, so an app that only uses `PostgREST`
# (or `Supabase`) never pays swift-syntax's build time. Nothing in the compiler keeps it that way:
# one convenient `import SwiftSyntax` in `PostgREST`, with its dependency, would quietly add that
# cost to every consumer. This script turns the boundary into a check.
#
# It does a clean build of `PostgREST` in its own build path, then looks for the build output of
# any module that swift-syntax declares. It checks swift-syntax modules, not the total number of
# compile steps, because the total changes each time a source file is added.
set -euo pipefail

cd "$(dirname "$0")/.."

build_path=".build/postgrest-dependency-check"
rm -rf "$build_path"

swift build --target PostgREST --build-path "$build_path"

syntax_sources="$build_path/checkouts/swift-syntax/Sources"
if [ ! -d "$syntax_sources" ]; then
  echo "error: no swift-syntax checkout at $syntax_sources; cannot list its modules." >&2
  exit 2
fi

# Only compiler output counts. swift-build leaves `<module>.swiftmodule` and `<module>.o` in
# `out/Products`; the native build system leaves `<module>.swiftmodule` and object files inside
# `<module>.build`. The native one also creates an empty `<module>.build` for every target in the
# graph, compiled or not, so the directory alone proves nothing. Sources and SwiftPM's prebuilt
# macro libraries are skipped: they are not compiled here.
compiled=()
for module_dir in "$syntax_sources"/*/; do
  module="$(basename "$module_dir")"
  found="$(
    find "$build_path" \
      \( -path "$build_path/checkouts" -o -path "$build_path/prebuilts" \) -prune -o \
      \( -name "$module.swiftmodule" -o -name "$module.o" -o -path "*/$module.build/*.o" \) \
      -print -quit
  )"
  if [ -n "$found" ]; then
    compiled+=("$module")
  fi
done

if [ "${#compiled[@]}" -ne 0 ]; then
  echo "error: building PostgREST compiled ${#compiled[@]} swift-syntax module(s):" >&2
  printf '  %s\n' "${compiled[@]}" >&2
  echo "PostgREST must not depend on swift-syntax. Keep macro code in PostgrestMacros." >&2
  exit 1
fi

echo "OK: building PostgREST compiled no swift-syntax module."
