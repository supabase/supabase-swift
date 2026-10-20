#!/usr/bin/env bash
# Fails when a Realtime test waits by yielding instead of on a signal with a bounded timeout.
#
# `Task.yield()` and `Task.megaYield()` loops pass or fail with scheduler load, so a test that
# needs one is flaky by construction. Wait on the stream, status or frame you care about, with
# a timeout (see `RealtimeTestHost` in Tests/RealtimeTests).
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

echo "No yield loops under Tests/RealtimeTests."
