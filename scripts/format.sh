#!/usr/bin/env bash
set -euo pipefail

find . \
  -path '*/Documentation/docc' -prune -o \
  -name '*.swift' \
  -not -path '*/.*' -print0 \
  | xargs -0 xcrun swift-format --ignore-unparsable-files --in-place
