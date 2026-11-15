#!/usr/bin/env bash
set -euo pipefail

find . \
  -name '*.swift' \
  -not -path '*/.*' -print0 \
  | xargs -0 xcrun swift-format --ignore-unparsable-files --in-place
