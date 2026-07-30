#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

SPEC=Sources/Storage/OpenAPI/openapi.json
NORMALIZED=$(mktemp -t openapi-normalized).json
trap 'rm -f "$NORMALIZED"' EXIT

# swift-openapi-generator only understands OpenAPI 3.0's scalar `type` +
# `nullable: true`, not JSON Schema 2020-12's nullable idioms: a `"type"`
# array (e.g. `["null", "integer"]`) or an `anyOf` branch of `{"type": "null"}`.
# Rewrite both to the OpenAPI 3.0 form before feeding the generator.
jq 'walk(
  if type == "object" then
    if (.type? | type) == "array" and (.type | index("null"))
    then . + {type: (.type - ["null"])[0], nullable: true}
    elif (.anyOf? | type) == "array" and (.anyOf | length == 2) and (.anyOf | any(. == {"type":"null"}))
    then (.anyOf | map(select(. != {"type":"null"})) | .[0]) as $other
      | (del(.anyOf) + $other + {nullable: true})
    else .
    end
  else .
  end
)' "$SPEC" > "$NORMALIZED"

swift run --package-path tools/openapi-generator swift-openapi-generator generate \
  "$NORMALIZED" \
  --config Sources/Storage/OpenAPI/openapi-generator-config.yaml \
  --output-directory Sources/Storage/Generated
