#!/usr/bin/env bash
# Formats all Swift sources (excluding docc catalogs, hidden directories, and
# generated code) with swift-format. Single source of truth for AGENTS.md,
# README.md, and CI.
set -euo pipefail

find . \
  -path '*/Documentation/docc' -prune -o \
  -path '*/Sources/Storage/Generated' -prune -o \
  -name '*.swift' \
  -not -path '*/.*' -print0 \
  | xargs -0 xcrun swift-format --ignore-unparsable-files --in-place
