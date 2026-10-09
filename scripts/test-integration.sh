#!/usr/bin/env bash
set -euo pipefail

# Mirrors the integration-tests job in .github/workflows/ci.yml. On macOS it uses the CLI's
# experimental native stack (no Docker); Linux has no native stack and falls back to Docker.
START_FLAGS=()
SWIFT_FLAGS=()
if [[ "$(uname)" == "Darwin" ]]; then
  export SUPABASE_EXPERIMENTAL_STACK=1
  START_FLAGS=(--runtime native --eager)
  SWIFT_FLAGS=(--triple arm64-apple-macosx14.0 -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays)
fi

run_suite() {
  local project="$1"
  shift
  (cd "$project" && supabase start ${START_FLAGS[@]+"${START_FLAGS[@]}"})
  trap "(cd '$project' && supabase stop)" EXIT
  swift test ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} "$@" --no-parallel
  (cd "$project" && supabase stop)
  trap - EXIT
}

run_suite Tests/IntegrationTests --filter IntegrationTests --skip verifyOTPForSecureEmailChange
run_suite Tests/IntegrationTests/supabase-secure-email-change --filter verifyOTPForSecureEmailChange
