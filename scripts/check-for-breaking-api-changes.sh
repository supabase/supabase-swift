#!/usr/bin/env bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftOpenAPIGenerator open source project
##
## Copyright (c) 2023 Apple Inc. and the SwiftOpenAPIGenerator project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftOpenAPIGenerator project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

# Exit status:
#   0  no breaking API changes
#   1  breaking API changes found (the "API breakage:" lines go to stdout)
#   2  the check could not run (bad environment, fetch failure, or a tool failure
#      that produced no "API breakage:" lines)
set -euo pipefail

EXIT_BREAKAGE=1
EXIT_CHECK_FAILED=2

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit "${EXIT_CHECK_FAILED}"; }

trap 'exit "${EXIT_CHECK_FAILED}"' ERR

CURRENT_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(git -C "${CURRENT_SCRIPT_DIR}" rev-parse --show-toplevel)"

log "Checking required environment variables..."
test -n "${BASELINE_REPO_URL:-}" || fatal "BASELINE_REPO_URL unset"
test -n "${BASELINE_TREEISH:-}" || fatal "BASELINE_TREEISH unset"

log "Fetching baseline: ${BASELINE_REPO_URL}#${BASELINE_TREEISH}..."
git -C "${REPO_ROOT}" fetch "${BASELINE_REPO_URL}" "${BASELINE_TREEISH}"
BASELINE_COMMIT=$(git -C "${REPO_ROOT}" rev-parse FETCH_HEAD)

log "Checking for API changes since ${BASELINE_REPO_URL}#${BASELINE_TREEISH} (${BASELINE_COMMIT})..."
SWIFT_OUTPUT=$(swift package --package-path "${REPO_ROOT}" diagnose-api-breaking-changes \
  "${BASELINE_COMMIT}" 2>&1) && RC=0 || RC=$?

echo "$SWIFT_OUTPUT" >&2

if [ "${RC}" -eq 0 ]; then
  log "✅ No breaking API changes detected."
  exit 0
fi

BREAKAGES=$(echo "$SWIFT_OUTPUT" | grep "API breakage:" || true)
if [ -n "${BREAKAGES}" ]; then
  echo "${BREAKAGES}"
  error "❌ Breaking API changes detected."
  exit "${EXIT_BREAKAGE}"
fi

fatal "diagnose-api-breaking-changes failed (exit ${RC}) and reported no API breakage. The check could not run; see the log above."
