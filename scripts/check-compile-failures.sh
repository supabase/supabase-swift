#!/usr/bin/env bash
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
