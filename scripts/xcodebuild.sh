#!/usr/bin/env bash
# Runs xcodebuild against the Supabase workspace for a given platform.
# Env vars (all optional, defaults match previous Makefile behavior):
#   PLATFORM             IOS | MACOS | MAC_CATALYST | TVOS | VISIONOS | WATCHOS (default: IOS)
#   CONFIG               Debug | Release (default: Debug)
#   SCHEME               Xcode scheme (default: Supabase)
#   WORKSPACE            Xcode workspace (default: Supabase.xcworkspace)
#   XCODEBUILD_ARGUMENT  xcodebuild action, e.g. build | test (default: test)
#   DERIVED_DATA_PATH    (default: ~/.derivedData/$CONFIG)
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

# `withMainSerialExecutor` (ConcurrencyExtras) hooks a process-wide task-enqueue global, not just
# the calling suite's own tasks. Swift Testing's default parallel execution runs unrelated suites
# concurrently in the same process, so while any withMainSerialExecutor-gated suite holds that
# hook, every other suite's tasks get silently forced onto the same serial queue too -- under a
# loaded CI simulator this backs up enough to blow through hardcoded test timeouts (e.g.
# AuthClientTests' assertAuthStateChanges) with spurious failures. Disable parallel test execution
# for `test` actions so no two suites run concurrently in the first place.
if [[ "$XCODEBUILD_ARGUMENT" == "test" ]]; then
  XCODEBUILD_ARGS+=(-parallel-testing-enabled NO)
fi

if command -v xcbeautify >/dev/null 2>&1; then
  xcodebuild "${XCODEBUILD_ARGS[@]}" | xcbeautify
else
  xcodebuild "${XCODEBUILD_ARGS[@]}"
fi
