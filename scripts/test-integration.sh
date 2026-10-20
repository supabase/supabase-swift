#!/usr/bin/env bash
set -euo pipefail

export INTEGRATION_TESTS=1

START_FLAGS=()
SWIFT_FLAGS=()
if [[ "$(uname)" == "Darwin" ]]; then
  export SUPABASE_EXPERIMENTAL_STACK=1
  START_FLAGS=(--runtime native --eager)
  SWIFT_FLAGS=(--triple "$(uname -m)-apple-macosx14.0" -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays)
fi

run_suite() {
  local project="$1"
  shift
  (cd "$project" && supabase start ${START_FLAGS[@]+"${START_FLAGS[@]}"})
  if [[ "$(uname)" != "Darwin" && "$project" == Tests/IntegrationTests ]]; then
    ./scripts/enable-storage-test-features.sh
    export STORAGE_TEST_FEATURES=1
  fi
  trap "(cd '$project' && supabase stop)" EXIT
  swift test ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} "$@" --no-parallel
  (cd "$project" && supabase stop)
  trap - EXIT
}

run_suite Tests/IntegrationTests --filter IntegrationTests --skip verifyOTPForSecureEmailChange
run_suite Tests/IntegrationTests/supabase-secure-email-change --filter verifyOTPForSecureEmailChange
