#!/usr/bin/env bash
set -euo pipefail

if [ ! -d tools/node/node_modules ]; then
  echo "tools/node dependencies are not installed. Run this once, then retry:" >&2
  echo "  npm ci --prefix tools/node" >&2
  exit 1
fi

( cd tools/node && npm run spell-check )
