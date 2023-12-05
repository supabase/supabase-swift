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

set -euo pipefail

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

CURRENT_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(git -C "${CURRENT_SCRIPT_DIR}" rev-parse --show-toplevel)"

log "Checking required environment variables..."
test -n "${BASELINE_REPO_URL:-}" || fatal "BASELINE_REPO_URL unset"
test -n "${BASELINE_TREEISH:-}" || fatal "BASELINE_TREEISH unset"

log "Fetching baseline: ${BASELINE_REPO_URL}#${BASELINE_TREEISH}..."
git -C "${REPO_ROOT}" fetch "${BASELINE_REPO_URL}" "${BASELINE_TREEISH}"
BASELINE_COMMIT=$(git -C "${REPO_ROOT}" rev-parse FETCH_HEAD)

log "Checking for API changes since ${BASELINE_REPO_URL}#${BASELINE_TREEISH} (${BASELINE_COMMIT})..."
swift package --package-path "${REPO_ROOT}" diagnose-api-breaking-changes \
  "${BASELINE_COMMIT}" \
  && RC=$? || RC=$?

if [ "${RC}" -ne 0 ]; then
  fatal "❌ Breaking API changes detected."
  exit "${RC}"
fi
log "✅ No breaking API changes detected."
