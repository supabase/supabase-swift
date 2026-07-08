# Adopt swift-openapi-generator for the Storage HTTP layer

Date: 2026-07-08
Status: Proposed

## Context

`Sources/Storage/StorageBucketApi.swift` and `Sources/Storage/StorageFileApi.swift` hand-build
every request (URL, method, query, body encoding) and hand-decode every response. This is
error-prone to keep in sync with the storage service and duplicates work already captured in the
service's own OpenAPI spec.

[supabase/storage#1215](https://github.com/supabase/storage/pull/1215) (open, targeting `master`)
fixes the generated OpenAPI spec's SDK-readiness: adds `operationId` to every operation, renames
the illegal `*` wildcard path param, registers `bucketSchema`/`objectSchema` as named components,
documents 401/403 responses, dedupes trailing-slash paths, and hides the schemaless S3 catch-all.
This makes the spec usable as codegen input for the first time.

Exporting the spec from PR #1215's branch (`npm run docs:export`) currently produces (default
single-tenant config, no image-transform/S3 flags):

- 25 paths, 54 operations (includes TUS resumable-upload routes, which don't exist in this SDK's
  current public API and are out of scope here — see [Scope](#scope))
- Named schemas: `authSchema`, `errorSchema`, `bucketSchema`, `objectSchema`
- Security scheme: `bearerAuth`

## Scope

This SDK's current (main-branch) public API surface: `StorageBucketApi` (bucket CRUD) and
`StorageFileApi` (object CRUD, list, move/copy, signed URLs, upload/update/download, info/exists,
transform options). TUS resumable uploads and the S3-compatible protocol don't exist in this SDK
today (they live only on the separate `refactor/storage-http-client` v3 branch, out of scope for
this effort) and are excluded.

**No public API or behavior changes.** Every existing method signature, type, and error stays
exactly as-is; the generated client becomes an internal implementation detail.

## Architecture

The generated OpenAPI client sits behind the existing facade classes, which already translate
between public types and wire format (e.g. `BucketOptions` → `BucketParameters` today):

```
storage.createBucket(_:options:)          ← public API, unchanged
  → StorageBucketApi (facade, hand-written)
    → maps public types to generated Operations input
    → calls generated Client (Operations.bucketCreate, ...)
      → StorageOpenAPITransport (new) → StorageHTTPSession.fetch/upload
    → maps generated Output back to public types, or throws StorageError
```

Callers of the SDK see no difference. The translation seam is exactly where it already lives.

## Spec vendoring & codegen tooling

- Vendor the spec at `Sources/Storage/OpenAPI/openapi.yaml`, exported from PR #1215's branch now;
  re-vendor once #1215 merges to `master`.
- Add `Sources/Storage/OpenAPI/openapi-generator-config.yaml` (generate `types` + `client`,
  `internal` access modifier).
- **Generate once, commit the output** — not a SwiftPM build plugin. Rationale: a build plugin
  regenerates on every build (cost paid by every consumer) and triggers Xcode's untrusted-plugin
  approval prompt for anyone depending on this package. Generating once keeps generated code
  diffable, formatted like the rest of the repo, and consumer-transparent.
- Don't add `apple/swift-openapi-generator` to the root `Package.swift` — it pulls in
  `swift-syntax`/`swift-argument-parser`/etc. that every consumer would resolve for a dev-only
  tool. Follow the existing `tools/node` precedent (used to isolate the cspell devDependency):
  an isolated `tools/openapi-generator` package (or a documented `swift run` invocation), driven
  by `scripts/generate-storage-openapi.sh`. Output committed into `Sources/Storage/Generated/`.
- Add `apple/swift-openapi-runtime` as a real dependency of the `Storage` target — the generated
  code imports `OpenAPIRuntime` types at runtime, so this one does ship to consumers (unlike the
  generator).
- CI: re-run generation and fail on diff, same spirit as the `./scripts/format.sh` check.

## Transport bridge & error mapping

- New `StorageOpenAPITransport: ClientTransport`
  (`Sources/Storage/OpenAPI/StorageOpenAPITransport.swift`) converts
  `OpenAPIRuntime.HTTPRequest`/`HTTPBody` to/from `URLRequest`/`Data` and calls
  `configuration.session.fetch`/`.upload` — the same injectable closures `StorageHTTPSession`
  already exposes. Existing Mocker-based tests keep working unchanged.
- The transport does not throw on non-2xx; it returns the raw response, matching
  `OpenAPIURLSession`'s contract. Error mapping happens in the facade: switch on the generated
  `Operations.*.Output` for documented error cases (401/403/404, now typed thanks to #1215) and
  construct `StorageError` from the typed payload; fall back to decoding `StorageError` from
  `.undocumented` responses for anything not in the spec (mirrors today's fallback in
  `StorageApi.execute`, `StorageApi.swift:115`).
- Left for a later release, not blocking this effort: migrating the transport from
  `StorageHTTPSession`-backed to `swift-openapi-urlsession` directly. Keeping
  `StorageHTTPSession` for now avoids any behavior change to custom-session/background-upload
  configuration.

## Multipart bodies (upload/update/uploadToSignedURL)

These use `multipart/form-data` today via the hand-written `MultipartFormData.swift`.
swift-openapi-generator supports typed multipart, but it's the least-proven part of this adoption.
Sequenced as its own milestone (see below) rather than blocking the rest of the migration on it.

## Testing

- Existing `StorageBucketAPITests`/`StorageFileAPITests` (Mocker-stubbed against `URLRequest`)
  keep working unchanged for migrated methods — the transport bridge preserves the outgoing
  request byte-for-byte.
- Add unit tests for `StorageOpenAPITransport` (request/response conversion round-trip) and for
  the facade's error-mapping switch (documented vs. undocumented error cases).

## Rollout

One design, four independently-mergeable milestones:

1. Vendor spec + tooling + `StorageOpenAPITransport`. No wiring, no behavior change.
2. Migrate `StorageBucketApi` (all JSON, smallest surface) — proves the pattern end-to-end.
3. Migrate JSON-only `StorageFileApi` operations: list, move, copy, remove, signed URLs, info,
   exists.
4. Migrate multipart upload/update/uploadToSignedURL and binary download.

Each milestone ships as its own `refactor(storage):` PR with no public API or behavior change.

## Out of scope / future work

- TUS resumable uploads and S3-compatible protocol (don't exist in this SDK today; live only on
  `refactor/storage-http-client`).
- Migrating the transport to `swift-openapi-urlsession` (deferred to a future release).
- Exposing generated types as public API (would be source-breaking; not pursued here).
