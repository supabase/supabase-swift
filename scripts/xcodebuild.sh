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

CONFIG="${CONFIG:-Debug}"
PLATFORM="${PLATFORM:-IOS}"
SCHEME="${SCHEME:-Supabase}"
WORKSPACE="${WORKSPACE:-Supabase.xcworkspace}"
XCODEBUILD_ARGUMENT="${XCODEBUILD_ARGUMENT:-test}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$HOME/.derivedData/$CONFIG}"

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

if command -v xcbeautify >/dev/null 2>&1; then
  xcodebuild "$XCODEBUILD_ARGUMENT" "${XCODEBUILD_FLAGS[@]}" | xcbeautify
else
  xcodebuild "$XCODEBUILD_ARGUMENT" "${XCODEBUILD_FLAGS[@]}"
fi
