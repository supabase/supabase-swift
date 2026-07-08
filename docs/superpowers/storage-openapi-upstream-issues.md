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
