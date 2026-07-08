#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift run --package-path tools/openapi-generator swift-openapi-generator generate \
  Sources/Storage/OpenAPI/openapi.json \
  --config Sources/Storage/OpenAPI/openapi-generator-config.yaml \
  --output-directory Sources/Storage/Generated
