#!/usr/bin/env bash
# Fails when a Realtime test waits by yielding or sleeping instead of on a signal with a bounded
# timeout.
#
# `Task.yield()` and `Task.megaYield()` loops pass or fail with scheduler load, so a test that
# needs one is flaky by construction. So does a `Task.sleep` that gives the code under test
# "enough time". Wait on the stream, status or frame you care about, with a timeout (see
# `RealtimeTestHost` in Tests/RealtimeTests). To stall a call, suspend with
# `Gate().pass()`.
#
# The Engine tests are excluded until the Engine is reworked; see the Realtime v3 project.
set -euo pipefail

cd "$(dirname "$0")/.."

if matches=$(grep -rnE 'Task\.(megaYield|yield)\(' Tests/RealtimeTests --include='*.swift' \
  --exclude=RealtimeEngineTests.swift --exclude=FakeRealtimeServerTests.swift); then
  echo "Yield loops are not allowed under Tests/RealtimeTests:" >&2
  echo "$matches" >&2
  exit 1
fi

if matches=$(grep -rn 'Task\.sleep(' Tests/RealtimeTests --include='*.swift'); then
  echo "Task.sleep is not allowed under Tests/RealtimeTests:" >&2
  echo "$matches" >&2
  exit 1
fi

echo "No yield loops or sleeps under Tests/RealtimeTests."
