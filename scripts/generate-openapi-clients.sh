#!/usr/bin/env bash
# Regenerates Sources/<Module>/Generated from openapi/<module>.json using
# tools/openapi-codegen. Add new modules to the MODULES array below as they
# get an OpenAPI spec.
set -euo pipefail

cd "$(dirname "$0")/.."

MODULES=(Storage)

for module in "${MODULES[@]}"; do
  spec="openapi/$(tr '[:upper:]' '[:lower:]' <<<"$module").json"
  output="Sources/$module/Generated"

  swift run --package-path tools/openapi-codegen openapi-codegen \
    --spec "$spec" \
    --output "$output" \
    --namespace "${module}BackendAPI"
done

./scripts/format.sh
