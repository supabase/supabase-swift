#!/usr/bin/env bash
set -euo pipefail

swift build \
  -q \
  -c release \
  --target Supabase \
  -Xswiftc -emit-module-interface \
  -Xswiftc -enable-library-evolution
