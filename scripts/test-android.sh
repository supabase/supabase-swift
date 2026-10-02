#!/usr/bin/env bash
# Cross-compiles the test suite for Android and runs it on an attached device or emulator.
#
# One-time setup — the host toolchain version must match the Swift SDK exactly, so Xcode's own
# toolchain cannot be used:
#
#   swiftly install 6.4.0 --use
#   swift sdk install https://download.swift.org/swift-6.4.0-release/android-sdk/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_android.artifactbundle.tar.gz \
#     --checksum 21fb555122a3d801ad943d48df7ebffdd8824de61c25c180bb792d3edaee0b43
#   curl -fSL -o ndk.zip https://dl.google.com/android/repository/android-ndk-r30-$(uname -s).zip && unzip -q ndk.zip
#
#
# Env vars (all optional except ANDROID_NDK_HOME):
#   ANDROID_NDK_HOME  NDK root (required; LTS r30 or newer)
#   SWIFT_SDK         Installed Swift SDK name (default: swift-6.4.0-RELEASE_android)
#   ARCH              aarch64 | x86_64 (default: aarch64)
#   API               Android API level to target (default: 23)
#   CONFIG            debug | release (default: debug)
#   SCRATCH_PATH      SwiftPM scratch path (default: .build-android)
#   TARGETS           Space-separated test targets (default: every unit-test target)
#   FILTER            Passed through to swift-testing's --filter
set -euo pipefail

: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to your Android NDK root}"
SWIFT_SDK="${SWIFT_SDK-swift-6.4.0-RELEASE_android}"
ARCH="${ARCH-aarch64}"
API="${API-23}"
CONFIG="${CONFIG-debug}"
SCRATCH_PATH="${SCRATCH_PATH-.build-android}"
# IntegrationTests needs a live Supabase instance, and PostgrestMacrosTests runs a compiler
# plugin on the host, so neither belongs in an on-device run.
TARGETS="${TARGETS-AuthTests DefaultIsolationTests FunctionsTests HelpersTests PostgRESTTests RealtimeTests StorageTests SupabaseTests}"
FILTER="${FILTER-}"

DEVICE_DIR=/data/local/tmp/supabase-swift-tests
# swift-snapshot-testing resolves `__Snapshots__` relative to the recorded #filePath, which the
# Swift SDK for Android maps onto this fixed location on device.
DEVICE_SNAPSHOT_DIR=/data/local/tmp/android-xctest/__Snapshots__

case "$ARCH" in
  aarch64) ABI=arm64-v8a ;;
  x86_64) ABI=x86_64 ;;
  *)
    echo "Unknown ARCH: $ARCH (expected aarch64 or x86_64)" >&2
    exit 1
    ;;
esac

for tool in swift adb; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "$tool not found on PATH" >&2
    exit 1
  }
done

if [[ "$(adb get-state 2>/dev/null)" != "device" ]]; then
  echo "No Android device or emulator attached. Start one, e.g.:" >&2
  echo "  emulator -avd <name> -no-window -no-audio -gpu swiftshader_indirect" >&2
  exit 1
fi

DEVICE_ABI=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
if [[ "$DEVICE_ABI" != "$ABI" ]]; then
  echo "Device ABI is $DEVICE_ABI but ARCH=$ARCH expects $ABI" >&2
  exit 1
fi

echo "==> Building tests for $ARCH-unknown-linux-android$API"
swift build \
  --build-tests \
  --swift-sdk "$SWIFT_SDK" \
  --triple "$ARCH-unknown-linux-android$API" \
  --configuration "$CONFIG" \
  --scratch-path "$SCRATCH_PATH"

PRODUCTS=$(find "$SCRATCH_PATH" -type d -path "*/Products/*-android-$ARCH" -print -quit)
[[ -n "$PRODUCTS" ]] || {
  echo "Could not locate build products under $SCRATCH_PATH" >&2
  exit 1
}

# The Swift runtime the cross-compiled binaries link against is not on the device, so it ships
# alongside them. SwiftPM keeps installed SDKs in a platform-dependent location.
SDK_BUNDLE=""
for root in "$HOME/Library/org.swift.swiftpm/swift-sdks" "$HOME/.swiftpm/swift-sdks"; do
  if [[ -d "$root/$SWIFT_SDK.artifactbundle" ]]; then
    SDK_BUNDLE="$root/$SWIFT_SDK.artifactbundle"
    break
  fi
done
[[ -n "$SDK_BUNDLE" ]] || {
  echo "Swift SDK '$SWIFT_SDK' not installed. Run 'swift sdk list' to see what is." >&2
  exit 1
}
SDK_LIBS="$SDK_BUNDLE/swift-android/swift-resources/usr/lib/swift-$ARCH/android"

# libc++_shared is an NDK library, not a Swift one, and nothing else pulls it onto the device.
LIBCXX=$(find "$ANDROID_NDK_HOME" -name libc++_shared.so -path "*$ARCH-linux-android*" -print -quit)
[[ -n "$LIBCXX" ]] || {
  echo "libc++_shared.so for $ARCH not found under $ANDROID_NDK_HOME" >&2
  exit 1
}

echo "==> Pushing to $DEVICE_DIR"
adb shell "rm -rf $DEVICE_DIR $DEVICE_SNAPSHOT_DIR && mkdir -p $DEVICE_DIR $DEVICE_SNAPSHOT_DIR"
adb push "$SDK_LIBS"/*.so "$DEVICE_DIR/" >/dev/null
adb push "$LIBCXX" "$DEVICE_DIR/" >/dev/null
adb push "$PRODUCTS"/*.so "$DEVICE_DIR/" >/dev/null
for bundle in "$PRODUCTS"/*.bundle; do
  adb push "$bundle" "$DEVICE_DIR/" >/dev/null
done
for runner in "$PRODUCTS"/*-test-runner; do
  adb push "$runner" "$DEVICE_DIR/" >/dev/null
done
for snapshots in Tests/*/__Snapshots__/*; do
  adb push "$snapshots" "$DEVICE_SNAPSHOT_DIR/" >/dev/null
done
adb shell "chmod +x $DEVICE_DIR/*-test-runner"

# The runner defaults to XCTest, which finds nothing: this package is Swift Testing only.
RUN_ARGS="--testing-library swift-testing"
[[ -n "$FILTER" ]] && RUN_ARGS="$RUN_ARGS --filter '$FILTER'"

status=0
for target in $TARGETS; do
  echo "==> $target"
  # adb shell reports its own exit status, not the remote command's, so the runner's has to be
  # echoed back over stdout and picked out here.
  output=$(adb shell "cd $DEVICE_DIR && LD_LIBRARY_PATH=$DEVICE_DIR ./$target-test-runner $RUN_ARGS; echo __exit=\$?" | tr -d '\r')
  grep -v '^__exit=' <<<"$output" || true
  grep -qx '__exit=0' <<<"$output" || status=1
done

exit $status
