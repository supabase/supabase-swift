# Storage OpenAPI Upload Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `upload`/`update`/`uploadToSignedURL` (all multipart) from hand-built
`MultipartFormData` requests to the generated OpenAPI client, with zero public API or behavior
change.

**Architecture:** Patch the vendored spec to declare a `multipart/form-data` requestBody (it's
currently entirely undeclared) for the three affected operations, regenerate, then replace the
two private helpers (`_uploadOrUpdate`, `_uploadToSignedURL`) that currently build
`MultipartFormData` by hand with calls to the generated client using its typed
`MultipartBody`/`MultipartPart` types.

**Tech Stack:** Swift 6.1, `swift-openapi-generator`'s multipart support (confirmed working via a
throwaway spike — see design doc), existing `StorageOpenAPITransport`/error-handling
infrastructure from the bucket API migration (unchanged, already handles arbitrary request
bodies).

**Design doc:** `docs/superpowers/specs/2026-07-08-storage-openapi-upload-design.md`

## Global Constraints

- No public API signature, type, or observable HTTP behavior may change. Every existing test in
  `Tests/StorageTests/StorageFileAPITests.swift` covering `upload`/`update`/`uploadToSignedURL`
  must keep passing after each task, **except** where a test asserts the exact serialized
  multipart body bytes — those may need re-recording (same discipline as the bucket API
  migration's JSON-body snapshots: only if the change is a semantically-inert reordering/framing
  difference, never a real content change, and confirmed byte-for-byte reasoned through before
  accepting).
- Run `./scripts/format.sh` before every commit that touches hand-written Swift files (it already
  excludes `Sources/Storage/Generated`).
- Platforms: iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+ (per `AGENTS.md`).
- The current `_getFinalPath(_:)` helper (`Sources/Storage/StorageFileApi.swift:979-981`) returns
  `"\(bucketId)/\(path)"` — a single combined path segment used when building a raw URL string.
  The generated `Operations.<op>.Input.Path` splits this into two separate fields, `bucketName`
  and `wildcard`. When migrating, pass `bucketId` and the **cleaned path alone** (not the
  `_getFinalPath`-combined string) to `bucketName`/`wildcard` respectively — combining them again
  would duplicate the bucket ID in the URL.

---

### Task 1: Patch the spec to declare multipart request bodies, regenerate

**Files:**
- Modify: `Sources/Storage/OpenAPI/openapi.json`
- Modify: `docs/superpowers/storage-openapi-upstream-issues.md`
- Modify (regenerated output): `Sources/Storage/Generated/Types.swift`,
  `Sources/Storage/Generated/Client.swift`

**Interfaces:**
- Produces: `Operations.objectUpload.Input.Body`, `Operations.objectUploadUpdate.Input.Body`,
  `Operations.objectUploadSigned.Input.Body` — each an enum with case
  `.multipartForm(OpenAPIRuntime.MultipartBody<...multipartFormPayload>)`, and
  `...multipartFormPayload` an enum with cases `.cacheControl(MultipartPart<cacheControlPayload>)`,
  `.metadata(MultipartPart<metadataPayload>)`, `.file(MultipartPart<filePayload>)`,
  `.undocumented(MultipartRawPart)`. Each `*Payload` struct has a single `body: HTTPBody` field.
  Consumed by Tasks 2-3.

- [ ] **Step 1: Add the multipart requestBody to the three operations**

Run this script to patch `Sources/Storage/OpenAPI/openapi.json` in place:

```bash
python3 -c "
import json

path = 'Sources/Storage/OpenAPI/openapi.json'
d = json.load(open(path))

multipart_schema = {
    'type': 'object',
    'properties': {
        'cacheControl': {'type': 'string'},
        'metadata': {'type': 'string'},
        'file': {'type': 'string', 'format': 'binary'}
    },
    'required': ['cacheControl', 'file']
}

request_body = {
    'required': True,
    'content': {
        'multipart/form-data': {
            'schema': multipart_schema
        }
    }
}

targets = [
    ('/object/{bucketName}/{wildcard}', 'post'),   # objectUpload
    ('/object/{bucketName}/{wildcard}', 'put'),    # objectUploadUpdate
    ('/object/upload/sign/{bucketName}/{wildcard}', 'put'),  # objectUploadSigned
]

for path_key, method in targets:
    op = d['paths'][path_key][method]
    assert 'requestBody' not in op, f'{op[\"operationId\"]} already has a requestBody'
    op['requestBody'] = request_body
    print('patched', op['operationId'])

with open(path, 'w') as f:
    json.dump(d, f, separators=(',', ':'))
"
```

Expected output:
```
patched objectUpload
patched objectUploadUpdate
patched objectUploadSigned
```

- [ ] **Step 2: Regenerate**

```bash
./scripts/generate-storage-openapi.sh
```

Expected: completes with no errors (the throwaway spike documented in the design doc already
confirmed this exact multipart shape generates cleanly — if you see an error here, something
about the *current* committed spec differs from what the spike used, stop and investigate rather
than guessing).

- [ ] **Step 3: Confirm the generated multipart types exist and inspect the file part's shape**

```bash
grep -n "enum objectUpload {" -A 60 Sources/Storage/Generated/Types.swift | grep -n "multipartFormPayload\|case cacheControl\|case metadata\|case file\|case undocumented"
```

Expected: shows the four cases (`cacheControl`, `metadata`, `file`, `undocumented`) under
`Operations.objectUpload.Input.Body.multipartFormPayload`.

Then check whether the generated `filePayload` struct or the `MultipartPart`/`MultipartBody`
machinery expose any way to set a per-part `Content-Type` header (the current hand-written
`MultipartFormData.append(_:withName:fileName:mimeType:)` sets one) — grep the generated file and
`OpenAPIRuntime`'s `MultipartPart`/`MultipartRawPart` types (find them via
`swift build --show-bin-path` then locate `.build/checkouts/swift-openapi-runtime/Sources/OpenAPIRuntime/Multipart/`)
for `headerFields`/`contentType`. Record what you find — Task 2 depends on this: if the typed
`.file(MultipartPart<filePayload>)` case has no way to set Content-Type, Task 2 must build the
file part via the `.undocumented(MultipartRawPart(headerFields:body:))` case instead, which does
expose full `HTTPFields` control.

- [ ] **Step 4: Verify the package builds**

```bash
swift build --target Storage
```

Expected: builds successfully (nothing consumes the new generated types yet).

- [ ] **Step 5: Log the upstream spec gap**

Add a new entry to `docs/superpowers/storage-openapi-upstream-issues.md` under `## Open`:

```markdown
- **`objectUpload`/`objectUploadUpdate`/`objectUploadSigned` have no declared request body at
  all.** Fastify's multipart handling isn't schema-validated the same way as JSON bodies, so the
  storage service's OpenAPI export never documented these operations' `multipart/form-data`
  request shape (`cacheControl`, optional `metadata`, and the file itself — currently sent with an
  **empty** multipart field name in this SDK's hand-written client, which needed a real field name
  to generate a usable typed member). Patched in the vendored copy at
  `Sources/Storage/OpenAPI/openapi.json` by adding a `multipart/form-data` requestBody with
  `cacheControl`/`metadata`/`file` fields to all three operations — see this repo's git history
  for the commit that landed it — not yet reported/fixed upstream. The real fix upstream would
  need to name the file field
  server-side too (or confirm the server doesn't actually key off the field name, in which case
  this SDK's request is already safe to send named without needing a server-side change first —
  verify this against server behavior before relying on it for anything beyond documentation).
```

- [ ] **Step 6: Commit**

```bash
git add Sources/Storage/OpenAPI/openapi.json Sources/Storage/Generated \
  docs/superpowers/storage-openapi-upstream-issues.md
git commit -m "feat(storage): add multipart requestBody to upload spec operations"
```

---

### Task 2: Migrate `upload`/`update` (`_uploadOrUpdate`)

**Files:**
- Modify: `Sources/Storage/StorageFileApi.swift:139-179` (the `_uploadOrUpdate` helper)
- Test: `Tests/StorageTests/StorageFileAPITests.swift` (re-record multipart snapshots if needed)

**Interfaces:**
- Consumes: `openAPIClient.objectUpload(_:)` / `.objectUploadUpdate(_:)`, both
  `async throws -> Operations.<op>.Output`; `Operations.<op>.Input.Body.multipartForm(...)`
  (Task 1).
- Produces: `_uploadOrUpdate` keeps its exact existing signature
  (`method:path:file:options: async throws -> FileUploadResponse`) — no change visible to
  `upload(_:data:)`, `upload(_:fileURL:)`, `update(_:data:)`, `update(_:fileURL:)`, which all call
  it unchanged.

- [ ] **Step 1: Confirm the existing tests describe current behavior**

```bash
swift test --filter StorageFileAPITests
```

Expected: PASS (current hand-written implementation). Note which specific tests cover
`upload`/`update` (grep for `func test.*[Uu]pload` and `func test.*[Uu]pdate` in the test file) —
these are today's acceptance gate.

- [ ] **Step 2: Build the multipart body**

Replace the body-construction portion of `_uploadOrUpdate`
(`Sources/Storage/StorageFileApi.swift:139-179`). The exact shape depends on Task 1 Step 3's
finding about per-part Content-Type support. If the typed `.file(MultipartPart<filePayload>)`
case has no Content-Type control, build the file part via `.undocumented(MultipartRawPart(...))`
instead, as shown here (adjust to use the typed case if Task 1 found it does support Content-Type
— in that case use `.file(.init(payload: .init(body: fileBody), filename: path.fileName))` and
drop the manual `Content-Type` header line since it'd be redundant):

```swift
  private func _uploadOrUpdate(
    method: HTTPTypes.HTTPRequest.Method,
    path: String,
    file: FileUpload,
    options: FileOptions?
  ) async throws -> FileUploadResponse {
    let options = options ?? defaultFileOptions

    let cleanPath = _removeEmptyFolders(path)

    var parts: [Operations.objectUpload.Input.Body.multipartFormPayload] = [
      .cacheControl(.init(payload: .init(body: HTTPBody(options.cacheControl))))
    ]

    if let metadata = options.metadata {
      parts.append(
        .metadata(.init(payload: .init(body: HTTPBody(encodeMetadata(metadata)))))
      )
    }

    let mimeType = options.contentType ?? mimeType(forPathExtension: path.pathExtension)
    var fileHeaders = HTTPFields()
    fileHeaders[.contentType] = mimeType
    fileHeaders[.contentDisposition] =
      #"form-data; name="file"; filename="\#(path.fileName)""#

    let fileBody: HTTPBody
    switch file {
    case .data(let data):
      fileBody = HTTPBody(data)
    case .url(let url):
      fileBody = HTTPBody(try Data(contentsOf: url))
    }

    parts.append(.undocumented(MultipartRawPart(headerFields: fileHeaders, body: fileBody)))

    var headers = options.headers.map { HTTPFields($0) } ?? HTTPFields()
    if method == .post {
      headers[.xUpsert] = "\(options.upsert)"
    }
    headers[.duplex] = options.duplex

    let input = Operations.objectUpload.Input(
      path: .init(bucketName: bucketId, wildcard: cleanPath),
      headers: .init(),
      body: .multipartForm(.init(parts))
    )

    // continued in Step 3 — the output handling and the PUT (update) call site
  }
```

> `Data(contentsOf:)` for the `.url` case reads the whole file into memory, same as the current
> `MultipartFormData.append(url, withName:)` path effectively does today via
> `formData.encode()` returning a single `Data` blob (confirm this in
> `Sources/Storage/MultipartFormData.swift` before assuming — if the current implementation
> genuinely streams from disk without loading it all into memory, and this migration would
> regress that, STOP and report it as a concern rather than silently accepting a memory-usage
> regression for large files).
>
> `options.headers` (extra custom headers) aren't expressible via the generated `Input.headers`
> struct (which only has `accept`) — they need to keep flowing through the transport's header
> merging (`StorageApi.executeRequestWithoutStatusCheck`, already shared with the bucket API
> migration), same as `x-upsert`/`Duplex` do today. Since the generated `Client` methods don't
> accept arbitrary extra headers directly, check whether `StorageApi.setHeader(_:forKey:)`
> (the per-instance mutable header bag already merged into every OpenAPI-routed request by
> `StorageOpenAPITransport`) is the right mechanism, or whether per-call custom headers
> (`options.headers`) need a different plumbing path — inspect how the bucket API migration
> handled per-instance headers (it didn't need per-CALL headers, only per-instance ones, so this
> is new territory Task 2 must resolve. If there's no clean way to pass per-call headers through
> the generated `Client`, that's a real gap — report it rather than silently dropping
> `options.headers` support).

- [ ] **Step 3: Call the operation and handle the two methods (POST=upload, PUT=update)**

`objectUpload` (POST) and `objectUploadUpdate` (PUT) are two different generated operations even
though today's hand-written code shares one method via an `HTTPTypes.HTTPRequest.Method`
parameter. Branch on `method` to call the right one, keeping the rest identical:

```swift
    let output: Operations.objectUpload.Output
    if method == .post {
      output = try await openAPIClient.objectUpload(input)
    } else {
      let updateOutput = try await openAPIClient.objectUploadUpdate(
        .init(path: input.path, headers: .init(), body: input.body)
      )
      // objectUploadUpdate.Output and objectUpload.Output are distinct generated types with the
      // same shape (.ok/.forbidden/.clientError/.undocumented, same {Id?, Key} success body) —
      // map updateOutput into the same handling below by writing the switch twice, once per
      // concrete Output type (mirrors how the bucket API migration's six methods each got their
      // own switch over their own concrete Output type — there is no shared protocol to unify
      // them, confirmed during the bucket API work).
      switch updateOutput {
      case .ok(let response):
        guard case .json(let body) = response.body else {
          throw StorageError.unexpectedResponse()
        }
        return FileUploadResponse(id: body.Id ?? "", path: path, fullPath: body.Key)
      case .forbidden(let response):
        throw try StorageError(decoding: response.body.json)
      case .clientError(let statusCode, let response):
        throw try StorageError(statusCode: statusCode, decoding: response.body.json)
      case .undocumented(let statusCode, let payload):
        throw await StorageError(
          statusCode: statusCode, undocumented: payload, decoder: configuration.decoder)
      }
    }

    switch output {
    case .ok(let response):
      guard case .json(let body) = response.body else {
        throw StorageError.unexpectedResponse()
      }
      return FileUploadResponse(id: body.Id ?? "", path: path, fullPath: body.Key)
    case .forbidden(let response):
      throw try StorageError(decoding: response.body.json)
    case .clientError(let statusCode, let response):
      throw try StorageError(statusCode: statusCode, decoding: response.body.json)
    case .undocumented(let statusCode, let payload):
      throw await StorageError(
        statusCode: statusCode, undocumented: payload, decoder: configuration.decoder)
    }
  }
```

> If this if/else duplication reads badly once you see it compiled, a cleaner shape is two
> completely separate private helpers (`_upload`/`_update`) instead of one `_uploadOrUpdate`
> branching on HTTP method — the current shared-helper design was chosen when both methods sent
> literally the same hand-built request differing only in `HTTPTypes.HTTPRequest.Method` and one
> header; now that they're two distinct generated operations with distinct `Output` types, that
> premise no longer holds. Use your judgment; either shape is acceptable as long as the four
> public methods' signatures and behavior stay identical — report which you chose and why.

- [ ] **Step 4: Run tests, re-record multipart snapshots if needed**

```bash
swift test --filter StorageFileAPITests
```

If a test fails only on the multipart `--data`/body bytes (boundary string, part ordering,
part framing) with the SAME logical content (same field names, same values, same file bytes),
that's expected — swift-openapi-generator's multipart encoder won't necessarily match
`MultipartFormData`'s exact byte-for-byte framing. Re-record following the same discipline as the
bucket API migration's JSON snapshots: confirm it's framing-only, not a real content difference,
before updating the test.

If a test fails for any other reason (wrong field values, wrong Content-Type, wrong status code
handling), that's a real bug — fix the implementation, don't touch the test.

- [ ] **Step 5: Format and commit**

```bash
./scripts/format.sh
swift test --filter StorageFileAPITests
git add Sources/Storage/StorageFileApi.swift Tests/StorageTests/StorageFileAPITests.swift
git commit -m "refactor(storage): migrate upload/update to generated OpenAPI client"
```

---

### Task 3: Migrate `uploadToSignedURL` (`_uploadToSignedURL`)

**Files:**
- Modify: `Sources/Storage/StorageFileApi.swift:939-974` (the `_uploadToSignedURL` helper)
- Test: `Tests/StorageTests/StorageFileAPITests.swift` (re-record multipart snapshots if needed)

**Interfaces:**
- Consumes: `openAPIClient.objectUploadSigned(_:)`, `Operations.objectUploadSigned.Input`
  (`path: .init(bucketName:wildcard:)`, `query: .init(token:)`,
  `body: .multipartForm(...)` — same `multipartFormPayload` shape as Task 2, generated separately
  per operation).
- Produces: `_uploadToSignedURL` keeps its exact existing signature
  (`path:token:file:options: async throws -> SignedURLUploadResponse`) — no change visible to
  `uploadToSignedURL(_:token:data:)`/`uploadToSignedURL(_:token:fileURL:)`.

- [ ] **Step 1: Confirm the existing tests describe current behavior**

```bash
swift test --filter StorageFileAPITests
```

Note which tests cover `uploadToSignedURL` (grep `func test.*SignedURL.*[Uu]pload` or similar).

- [ ] **Step 2: Migrate**

Reuse the exact multipart-part-building logic from Task 2 Step 2 (same `cacheControl`/`metadata`/
file-part shape — factor it into a shared private helper if that reads cleanly, e.g.
`_buildMultipartParts(file:options:path:) -> [Operations.objectUpload.Input.Body.multipartFormPayload]`,
but note `Operations.objectUploadSigned.Input.Body.multipartFormPayload` is a **separate generated
type** even though structurally identical — a shared helper would need to either duplicate the
tiny part-building logic per operation, or you accept the duplication given there's no shared
protocol across generated types, same conclusion Task 2 and the bucket API migration both reached
independently). Replace `Sources/Storage/StorageFileApi.swift:939-974`:

```swift
  private func _uploadToSignedURL(
    path: String,
    token: String,
    file: FileUpload,
    options: FileOptions?
  ) async throws -> SignedURLUploadResponse {
    let options = options ?? defaultFileOptions

    var parts: [Operations.objectUploadSigned.Input.Body.multipartFormPayload] = [
      .cacheControl(.init(payload: .init(body: HTTPBody(options.cacheControl))))
    ]

    if let metadata = options.metadata {
      parts.append(
        .metadata(.init(payload: .init(body: HTTPBody(encodeMetadata(metadata)))))
      )
    }

    let mimeType = options.contentType ?? mimeType(forPathExtension: path.pathExtension)
    var fileHeaders = HTTPFields()
    fileHeaders[.contentType] = mimeType
    fileHeaders[.contentDisposition] =
      #"form-data; name="file"; filename="\#(path.fileName)""#

    let fileBody: HTTPBody
    switch file {
    case .data(let data):
      fileBody = HTTPBody(data)
    case .url(let url):
      fileBody = HTTPBody(try Data(contentsOf: url))
    }

    parts.append(.undocumented(MultipartRawPart(headerFields: fileHeaders, body: fileBody)))

    let output = try await openAPIClient.objectUploadSigned(
      .init(
        path: .init(bucketName: bucketId, wildcard: path),
        query: .init(token: token),
        headers: .init(),
        body: .multipartForm(.init(parts))
      )
    )

    switch output {
    case .ok(let response):
      guard case .json(let body) = response.body else {
        throw StorageError.unexpectedResponse()
      }
      return SignedURLUploadResponse(path: path, fullPath: body.Key)
    case .forbidden(let response):
      throw try StorageError(decoding: response.body.json)
    case .clientError(let statusCode, let response):
      throw try StorageError(statusCode: statusCode, decoding: response.body.json)
    case .undocumented(let statusCode, let payload):
      throw await StorageError(
        statusCode: statusCode, undocumented: payload, decoder: configuration.decoder)
    }
  }
```

> Note this operation's success response is `{Key}` only (no `Id`), matching
> `SignedURLUploadResponse`'s existing shape (`path`, `fullPath` — no `id` field) — confirmed
> against the vendored spec during planning. If the generated `Output.Ok.Body.jsonPayload` here
> has an `Id` field too, something changed since planning; adjust and note it in your report
> rather than silently ignoring the discrepancy.
>
> This operation applies `x-upsert`/`Duplex`/`options.headers` too (check the current
> pre-migration code at `Sources/Storage/StorageFileApi.swift:946-949`) — carry those over using
> whatever mechanism Task 2 settled on for the same problem (per-call custom headers through the
> generated client).

- [ ] **Step 3: Run tests, re-record if needed**

```bash
swift test --filter StorageFileAPITests
```

Same re-recording discipline as Task 2 Step 4 — framing-only differences are fine, content
differences are bugs.

- [ ] **Step 4: Format and commit**

```bash
./scripts/format.sh
swift test --filter StorageFileAPITests
git add Sources/Storage/StorageFileApi.swift Tests/StorageTests/StorageFileAPITests.swift
git commit -m "refactor(storage): migrate uploadToSignedURL to generated OpenAPI client"
```

---

### Task 4: Remove dead `MultipartFormData`, run the full suite

**Files:**
- Delete: `Sources/Storage/MultipartFormData.swift` (if confirmed fully unused)
- Delete (if only used by the above): its paired test file, if one exists under
  `Tests/StorageTests/`

**Interfaces:** None — cleanup only.

- [ ] **Step 1: Confirm `MultipartFormData` has no remaining callers**

```bash
grep -rn "MultipartFormData(" Sources/Storage Tests/StorageTests
```

Expected: zero hits (Tasks 2-3 were its only callers, per the design doc's investigation).

- [ ] **Step 2: Remove it**

```bash
git rm Sources/Storage/MultipartFormData.swift
```

If a dedicated `Tests/StorageTests/MultipartFormDataTests.swift` (or similarly named) file exists
and only tests this now-deleted type, remove it too — check first with
`grep -l "MultipartFormData" Tests/StorageTests/*.swift`.

- [ ] **Step 3: Run the full test suite**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild
```

Expected: all tests pass, including every test in `StorageFileAPITests` and the rest of the
existing suite (no regressions in `StorageBucketAPITests`, `StorageOpenAPITransportTests`, etc.).

- [ ] **Step 4: Format everything touched by this plan**

```bash
./scripts/format.sh
git status
```

Expected: only files this plan touched show as modified. If `format.sh` reformats unrelated
files, revert those with `git checkout -- <file>`.

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "refactor(storage): remove MultipartFormData, superseded by generated OpenAPI client"
```

---

## What's next

`download(path:options:query:cacheNonce:)` (binary response streaming) is the last piece of the
original Milestone 4 scope and gets its own follow-up plan, since it's a different concern
(response body streaming, not request multipart construction) with its own unknowns to verify
against the generated code first.
