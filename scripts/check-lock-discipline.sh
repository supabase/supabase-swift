#!/usr/bin/env bash
# Fails when the Realtime engine core finishes a stream, cancels a task, resumes a continuation
# or logs outside a `later { }` block. EngineState runs under the engine's lock, and each of those
# calls can run code that takes the lock again (`onTermination`, cancellation handlers) or app
# code (the log handler), so they must be deferred until the lock is released.
#
# `outbound?.finish()` is the one exception: the frame queue has no `onTermination`, and finishing
# it under the lock keeps frames from going out after the close.
#
# A SwiftLint custom rule is a single regex and cannot tell whether a line sits inside a
# multi-line `later { }` block, so this tracks the block's braces instead.
set -euo pipefail

file="${1:-Sources/Realtime/Engine/EngineState.swift}"

awk '
  function count(text, char,   n) { n = gsub(char, "", text); return n }
  {
    code = $0
    sub(/\/\/.*/, "", code)
    if (depth > 0) {
      depth += count(code, "{") - count(code, "}")
      next
    }
    start = index(code, "later {")
    if (start > 0) {
      prefix = substr(code, 1, start - 1)
      rest = substr(code, start)
      depth = count(rest, "{") - count(rest, "}")
      code = prefix
    }
    if (code ~ /outbound\?\.finish\(\)/) next
    if (code ~ /\.finish\(\)|\.cancel\(\)|\.resume\(|logger\./) {
      printf "%s:%d: call it inside later { } so it runs after the lock is released\n", FILENAME, FNR
      printf "  %s\n", $0
      failed = 1
    }
  }
  END { exit failed }
' "$file"
