# Migrate upload/update/uploadToSignedURL to the generated OpenAPI client

Date: 2026-07-08
Status: Proposed

## Context

This is Milestone 4 of [2026-07-08-storage-openapi-generator-design.md](2026-07-08-storage-openapi-generator-design.md)
("multipart upload/update/uploadToSignedURL and binary download"), picked up after Milestones 1-2
(bucket API + plumbing) shipped and were reviewed clean.

`StorageFileApi.upload(_:data:)`, `upload(_:fileURL:)`, `update(_:data:)`, `update(_:fileURL:)`,
and `uploadToSignedURL(...)` all funnel through a single private helper,
`_uploadOrUpdate(method:path:file:options:)` (`Sources/Storage/StorageFileApi.swift`), which:

- Builds a `MultipartFormData` body by hand: a `cacheControl` field (always sent), an optional
  `metadata` field (JSON-encoded), and the file itself as an **unnamed** part
  (`formData.append(data, withName: "", fileName:, mimeType:)`).
- Sends `x-upsert` and `Duplex` as headers, not multipart fields.
- Decodes a `{ Key, Id }` JSON response into `FileUploadResponse`.

The vendored spec (`Sources/Storage/OpenAPI/openapi.json`) declares the response schema for
`POST /object/{bucketName}/{wildcard}` (`objectUpload`) — `{Id, Key}`, matching the hand-written
`UploadResponse` exactly — but has **no `requestBody` at all**. Fastify's multipart handling isn't
schema-validated the same way as JSON bodies, so the storage service's OpenAPI export never
documented it. Without a declared request body, swift-openapi-generator's `Input` type for this
operation has no `body` parameter — there is nothing to send a request through today.

## Scope

- `upload(_:data:options:)`, `upload(_:fileURL:options:)`, `update(_:data:options:)`,
  `update(_:fileURL:options:)`, `uploadToSignedURL(_:token:data:options:)`,
  `uploadToSignedURL(_:token:fileURL:options:)` — all six route through the shared
  `_uploadOrUpdate` helper and get migrated together as one unit of work.
- `download(path:options:query:cacheNonce:)` (binary response body) is explicitly **out of
  scope** — different concern (streaming response, not multipart request), its own follow-up.
- No public API or behavior change, same bar as Milestones 1-2.

## Architecture

1. **Patch the vendored spec** to add a `multipart/form-data` requestBody to the three affected
   operations (`POST /object/{bucketName}/{wildcard}`, `PUT /object/{bucketName}/{wildcard}`,
   `PUT /object/upload/sign/{bucketName}/{wildcard}`), declaring the real parts:
   `cacheControl` (string, required), `metadata` (string, optional), and the file part (binary).
   Log this as a fourth entry in `docs/superpowers/storage-openapi-upstream-issues.md`, matching
   the three fixes already tracked there from Milestones 1-2.
2. **De-risk the empty part name before writing any facade code.** The current file part has no
   name (`withName: ""`) — multipart field names aren't observable to API callers, so naming it
   explicitly in the spec (e.g. `""` → some placeholder name) is a safe, semantics-preserving
   change on the wire, *if* the server's multipart parser matches by position/content-type rather
   than by field name for this part. This needs verification against the real storage service
   behavior (or its source, if inspectable) before assuming it's safe — this is the single biggest
   unknown in this design, called out explicitly rather than glossed over.
3. **Spike first:** patch the spec, regenerate, and inspect the generated multipart `Input.body`
   type in isolation (no facade changes yet) to confirm swift-openapi-generator produces something
   usable. If it doesn't (e.g. errors, or an unworkable shape), fall back to option considered and
   rejected in brainstorming — hand-built multipart body, generated client only for response
   decoding — documented here so it isn't silently re-litigated if the spike fails.
4. **Migrate `_uploadOrUpdate`** to build the generated multipart `Input.body` instead of the
   hand-written `MultipartFormData`, once the spike confirms feasibility. Keep the response
   decoding and error handling identical to the bucket methods' established pattern (`.ok`
   decodes `{Id, Key}` into `FileUploadResponse`; `.forbidden`/`.clientError`/`.undocumented`
   decode `StorageError` from the real error body, per the fix already landed in Milestones 1-2).
5. **Verify `StorageOpenAPITransport` handles multipart bodies correctly** — it currently collects
   `HTTPBody` into `Data` and forwards headers with two narrow normalizations (drop `Accept`,
   strip `charset=utf-8` from JSON `Content-Type`). A multipart request's `Content-Type` is
   `multipart/form-data; boundary=...`, which the charset-strip condition (exact match on
   `application/json; charset=utf-8`) won't touch — should pass through unchanged, but confirm
   with a test rather than assume.
6. **File-URL streaming**: the current `.url(let url)` case in `FileUpload.encode(to:withPath:)`
   appends the URL directly to `MultipartFormData` for large-file handling. Confirm whether
   swift-openapi-generator's multipart support has an equivalent (a body source that doesn't
   require loading the whole file into memory) or whether this becomes a behavior-relevant gap
   that needs explicit handling (e.g., falling back to reading the file into `Data` — acceptable
   only if flagged and confirmed non-regressive for the file sizes this SDK is expected to handle).

## Testing

Existing `StorageFileAPITests` snapshot tests (multipart body assertions) are the acceptance gate,
same discipline as Milestones 1-2: request bytes should stay identical; if the generated
multipart encoder produces a different (but semantically equivalent) boundary/ordering, that's a
snapshot re-record, not silently accepted — same standard applied to `createBucket`'s JSON body
in Milestone 1-2.

## Risks / Open Questions

- **Empty multipart field name**: the biggest unknown (see Architecture step 2). This could
  invalidate the "safe to add a name" assumption if the server actually inspects the field name.
  Needs verification before or during the spike.
- **File-URL streaming parity**: swift-openapi-generator's multipart body types may not support
  streaming from a file URL the way the current implementation intends to (see Architecture step
  6) — resolve during the spike, not assumed away.
- If the spike shows swift-openapi-generator's multipart support isn't viable for this shape, the
  fallback (generated client for response/URL only, hand-written multipart body unchanged) is
  documented above so the effort isn't wasted — that fallback still achieves typed response
  decoding and shared error handling, just not typed request construction.

## Out of scope / future work

- `download(path:options:query:cacheNonce:)` — binary response streaming, separate design.
- The S3-compatible protocol and TUS resumable uploads remain out of scope for this SDK (per the
  original design doc) — this only ever existed on the separate `refactor/storage-http-client`
  branch.
