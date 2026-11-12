#!/usr/bin/env bash
# Runs the Maestro UI tests against the local Supabase stack.
#
# Usage: maestro/run.sh [flow.yaml ...]     (default: every flow in maestro/flows)
#
# Env vars (all optional):
#   SIMULATOR   Simulator name (default: iPhone 18 Pro)
#   SKIP_BUILD  Set to 1 to reuse the last build
#   SKIP_RESET  Set to 1 to keep the database as it is
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$PROJECT/../.." && pwd)"
SIMULATOR="${SIMULATOR-iPhone 18 Pro}"
DERIVED_DATA="$ROOT/.build/reminders"
APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Reminders.app"

UDID="$(xcrun simctl list --json devices available \
  | jq -r --arg name "$SIMULATOR" \
    '[.devices | to_entries | sort_by(.key) | .[].value[] | select(.name == $name)] | last | .udid')"
if [[ -z "$UDID" || "$UDID" == "null" ]]; then
  echo "No available simulator named '$SIMULATOR'." >&2
  exit 1
fi

if [[ -z "${SKIP_RESET-}" ]]; then
  (cd "$PROJECT" && supabase db reset)
fi

if [[ -z "${SKIP_BUILD-}" ]]; then
  xcodebuild -quiet \
    -workspace "$ROOT/Supabase.xcworkspace" \
    -scheme Reminders \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    build
fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl install "$UDID" "$APP"

if [[ $# -eq 0 ]]; then
  set -- "$HERE/flows"
fi

maestro --device "$UDID" test "$@"
