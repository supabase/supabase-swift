# Upstream issues found in supabase/storage's OpenAPI spec

Tracking bugs/gaps found in the spec exported from
[supabase/storage#1215](https://github.com/supabase/storage/pull/1215) (`npm run docs:export`)
while adopting swift-openapi-generator in this repo. File these upstream once confirmed against
`master`.

## Open

- **Invalid OpenAPI 3.1 nullable-type-array syntax in a 3.0.3 document.** The document declares
  `openapi: "3.0.3"` but 4 schema properties use OpenAPI 3.1-only array-form nullable types
  (`"type": ["null", "integer"]`), which isn't valid in 3.0.x (nullable there must be
  `"type": "integer", "nullable": true`). swift-openapi-generator (1.13.0) hard-fails parsing on
  this. Found while running Task 2 of
  `docs/superpowers/plans/2026-07-08-storage-openapi-generator.md`; patched in the vendored copy
  at `Sources/Storage/OpenAPI/openapi.json` (commit a445a3a2), not yet reported/fixed upstream.
  Locations in the exported spec:
  - `components.schemas.bucketSchema.properties.file_size_limit` — `["null", "integer"]`
  - `components.schemas.bucketSchema.properties.allowed_mime_types` — `["null", "array"]`
  - `paths./object/sign/{bucketName}.post.responses.200.content.application/json.schema.items.properties.error` — `["null", "string"]`
  - `paths./object/sign/{bucketName}.post.responses.200.content.application/json.schema.items.properties.signedURL` — `["null", "string"]`

- **Second, larger batch of OpenAPI 3.1-only `anyOf` nullable syntax, also invalid under the
  declared 3.0.3 version.** 12 properties use `anyOf: [<schema>, {"type": "null"}]` (the other
  JSON-Schema-2020-12/3.1 way of expressing nullable), which 3.0.3 also doesn't support — nullable
  there must be a plain `nullable: true` on the schema itself. swift-openapi-generator failed with
  `Cannot initialize JSONType from invalid String value null` on `objectSchema.properties.id` and
  the `/object/copy` response schema. Found while running Task 2 (after the first batch was
  already fixed); patched by merging each non-null branch's keywords onto the parent schema and
  setting `nullable: true` (commit 4651f5e3), not yet reported/fixed upstream. Exact locations not
  individually enumerated here — see commit 4651f5e3's diff in this repo's history for the before
  state if needed; a full re-scan after the fix confirmed zero remaining `type`-array or
  `anyOf`-with-null occurrences anywhere in the document.

- **`bucketUpdate`'s request body schema lists properties in `required` that don't exist at the
  top level of `properties`.** swift-openapi-generator emits two non-fatal warnings for this
  during generation (`public`/`file_size_limit`/`allowed_mime_types` appear in `required` without
  a matching sibling in `properties` — likely because the real properties live inside an `anyOf`
  branch rather than directly on the body schema). Doesn't block generation, not yet fixed on
  either side. Reproduce with `./scripts/generate-storage-openapi.sh` and read the warnings on
  `bucketUpdate`.
