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

- **`bucketUpdate`'s request body schema had a redundant top-level `anyOf` that made
  swift-openapi-generator drop the schema's sibling `properties` entirely.** The `PUT
  /bucket/{bucketId}` request body declared `type: object`, `minProperties: 1`, and a normal
  `properties` object (`public`/`file_size_limit`/`allowed_mime_types`) — but ALSO a top-level
  `anyOf: [{required:[public]}, {required:[file_size_limit]}, {required:[allowed_mime_types]}]`
  expressing "at least one of these three is present", which is already fully implied by
  `minProperties: 1` given the schema has no other properties. swift-openapi-generator treats a
  schema with a top-level `anyOf` as anyOf-driven and ignores the co-located `properties` (it
  first only emitted two non-fatal warnings during generation, but confirmed while attempting
  Task 10 of `docs/superpowers/plans/2026-07-08-storage-openapi-generator.md` that this actually
  produces a request body type with zero usable properties — every field permanently `nil`, an
  unusable/misleading generated type, not just a warning). Fixed in the vendored copy by deleting
  the redundant top-level `anyOf` (kept `minProperties: 1` and `properties` — no semantic change,
  the server still enforces "at least one field" and the old hand-written client never enforced it
  client-side either), regenerated successfully with a normal populated body type. Not yet
  reported/fixed upstream — the real fix upstream is likely just deleting that same redundant
  `anyOf` from wherever `updateBucket.ts`'s route schema declares it (probably a documentation-only
  addition since `minProperties: 1` already carries the constraint).

- **`objectUpload`/`objectUploadUpdate`/`objectUploadSigned` have no declared request body at
  all.** Fastify's multipart handling isn't schema-validated the same way as JSON bodies, so the
  storage service's OpenAPI export never documented these operations' `multipart/form-data`
  request shape (`cacheControl`, optional `metadata`, and the file itself — currently sent with an
  **empty** multipart field name in this SDK's hand-written client, which needed a real field name
  to generate a usable typed member). Patched in the vendored copy at
  `Sources/Storage/OpenAPI/openapi.json` by adding a `multipart/form-data` requestBody with
  `cacheControl`/`metadata`/`file` fields to all three operations — see this repo's git history
  for the commit that landed it — not yet reported/fixed upstream. The real fix upstream would
  need to name the file field server-side too (or confirm the server doesn't actually key off the
  field name, in which case this SDK's request is already safe to send named without needing a
  server-side change first — verify this against server behavior before relying on it for anything
  beyond documentation).

  Side finding while regenerating with this schema: swift-openapi-generator's typed multipart API
  hardcodes `Content-Type: application/octet-stream` for a `format: binary` field with no way to
  override it per call (confirmed in the generated `Client.swift`'s `objectUpload` serializer —
  the `.file` case always calls `converter.setRequiredRequestBodyAsBinary(..., contentType:
  "application/octet-stream")`). This SDK needs to send the file's real MIME type (e.g.
  `image/png`), so the file part must be built via the generator's
  `.undocumented(OpenAPIRuntime.MultipartRawPart(headerFields:body:))` escape hatch instead of the
  typed `.file(...)` case, setting `Content-Type`/`Content-Disposition` explicitly. Not an
  upstream spec issue (this is a swift-openapi-generator limitation, not a supabase/storage spec
  bug) — noted here only because it directly shapes how this repo consumes the schema above.
