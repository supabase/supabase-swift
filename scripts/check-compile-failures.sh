#!/usr/bin/env bash
# Checks that every fixture in Tests/CompileFailures fails to compile, for the expected reason.
#
# Some properties of the typed PostgREST API are "this cannot be written". A test target cannot
# hold code that does not compile, so these fixtures belong to no target. This script builds the
# PostgREST module, type-checks each fixture against it, and fails if a fixture compiles, or fails
# with a diagnostic other than the one its `// expected-error:` line names. The expected text keeps
# an unrelated break (a renamed type, a missing import) from passing as the intended rejection.
#
# Usage: ./scripts/check-compile-failures.sh [debug|release]
set -euo pipefail

cd "$(dirname "$0")/.."
config="${1:-debug}"

swift build -c "$config" --target PostgREST
bin="$(swift build -c "$config" --show-bin-path)"

status=0
for fixture in Tests/CompileFailures/*.swift; do
  expected="$(sed -n 's|^// expected-error: ||p' "$fixture")"
  if [ -z "$expected" ]; then
    echo "FAIL $fixture: no '// expected-error:' line"
    status=1
    continue
  fi

  # Modules sit in the bin path itself (swift-build) or in its Modules folder (native build).
  if output="$(swiftc -typecheck -I "$bin" -I "$bin/Modules" "$fixture" 2>&1)"; then
    echo "FAIL $fixture: compiled, but must not"
    status=1
    continue
  fi
  errors="$(grep "^$fixture:[0-9]*:[0-9]*: error: " <<<"$output" || true)"
  if [ "$(grep -c . <<<"$errors")" -ne 1 ] || [ "${errors#*: error: }" != "$expected" ]; then
    echo "FAIL $fixture: expected exactly one error, '$expected'. Got:"
    echo "$output"
    status=1
  else
    echo "ok   $fixture"
  fi
done
exit "$status"
