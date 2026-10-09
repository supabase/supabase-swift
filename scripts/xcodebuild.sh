#!/usr/bin/env bash
# Runs xcodebuild against the Supabase workspace for a given platform.
# Env vars (all optional, defaults match previous Makefile behavior):
#   PLATFORM             IOS | MACOS | MAC_CATALYST | TVOS | VISIONOS | WATCHOS (default: IOS)
#   CONFIG               Debug | Release (default: Debug)
#   SCHEME               Xcode scheme (default: Supabase)
#   WORKSPACE            Xcode workspace (default: Supabase.xcworkspace)
#   XCODEBUILD_ARGUMENT  xcodebuild action, e.g. build | test (default: test)
#   DERIVED_DATA_PATH    (default: ~/.derivedData/$CONFIG)
#   WARNINGS_FILE        when set, compiler warnings are appended to this file instead of
#                        being annotated here, and the `warnings` CI job annotates the
#                        deduplicated union of every job's file (see collect-warnings.sh)
set -euo pipefail

CONFIG="${CONFIG-Debug}"
PLATFORM="${PLATFORM-IOS}"
SCHEME="${SCHEME-Supabase}"
WORKSPACE="${WORKSPACE-Supabase.xcworkspace}"
XCODEBUILD_ARGUMENT="${XCODEBUILD_ARGUMENT-test}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH-$HOME/.derivedData/$CONFIG}"

udid_for() {
  xcrun simctl list --json devices available "$1" \
    | jq -r '[.devices|to_entries|sort_by(.key)|reverse|.[].value|select(length > 0)|.[0]][0].udid'
}

case "$PLATFORM" in
  IOS) DESTINATION="platform=iOS Simulator,id=$(udid_for iOS)" ;;
  MACOS) DESTINATION="platform=macOS" ;;
  MAC_CATALYST) DESTINATION="platform=macOS,variant=Mac Catalyst" ;;
  TVOS) DESTINATION="platform=tvOS Simulator,id=$(udid_for tvOS)" ;;
  VISIONOS) DESTINATION="platform=visionOS Simulator,id=$(udid_for visionOS)" ;;
  WATCHOS) DESTINATION="platform=watchOS Simulator,id=$(udid_for watchOS)" ;;
  *)
    echo "Unknown PLATFORM: $PLATFORM" >&2
    exit 1
    ;;
esac

PLATFORM_ID=$(echo "$DESTINATION" | sed -E "s/.+,id=(.+)/\1/")
if [[ -n "$PLATFORM_ID" ]]; then
  xcrun simctl boot "$PLATFORM_ID" && open -a Simulator --args -CurrentDeviceUDID "$PLATFORM_ID" || true
fi

XCODEBUILD_FLAGS=(
  -configuration "$CONFIG"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -destination "$DESTINATION"
  -scheme "$SCHEME"
  -skipMacroValidation
  -workspace "$WORKSPACE"
)

XCODEBUILD_ARGS=()
if [[ -n "$XCODEBUILD_ARGUMENT" ]]; then
  XCODEBUILD_ARGS+=("$XCODEBUILD_ARGUMENT")
fi
XCODEBUILD_ARGS+=("${XCODEBUILD_FLAGS[@]}")

RAW_LOG=/dev/null
if [[ -n "${WARNINGS_FILE-}" ]]; then
  RAW_LOG="$(mktemp)"
  trap 'rm -f "$RAW_LOG"' EXIT
fi

beautify() {
  if [[ -n "${WARNINGS_FILE-}" ]]; then
    # xcbeautify annotates every warning it sees, which the matrix then repeats once per
    # platform, Xcode version and configuration. Drop its warning and notice annotations
    # and let the `warnings` job annotate the deduplicated union instead. Error
    # annotations are kept: those belong to the job that failed.
    xcbeautify | grep --line-buffered -Ev '^::(warning|notice)' || true
  else
    xcbeautify
  fi
}

STATUS=0
if command -v xcbeautify >/dev/null 2>&1; then
  xcodebuild "${XCODEBUILD_ARGS[@]}" | tee "$RAW_LOG" | beautify || STATUS=$?
else
  xcodebuild "${XCODEBUILD_ARGS[@]}" | tee "$RAW_LOG" || STATUS=$?
fi

if [[ -n "${WARNINGS_FILE-}" ]]; then
  "$(dirname "${BASH_SOURCE[0]}")/collect-warnings.sh" "$RAW_LOG" >>"$WARNINGS_FILE"
fi

exit "$STATUS"
