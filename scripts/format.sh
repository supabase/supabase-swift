#!/usr/bin/env bash
# Formats all Swift sources (excluding docc catalogs and hidden directories)
# with swift-format. Single source of truth for AGENTS.md, README.md, and CI.
set -euo pipefail

find . \
  -path '*/Documentation/docc' -prune -o \
  -name '*.swift' \
  -not -path '*/.*' -print0 \
  | xargs -0 xcrun swift-format --ignore-unparsable-files --in-place
