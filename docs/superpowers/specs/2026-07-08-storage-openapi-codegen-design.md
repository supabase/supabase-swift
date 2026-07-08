# OpenAPI-driven Swift codegen for Storage

**Date:** 2026-07-08
**Status:** Approved for planning

## Goal

Build a generic OpenAPI-to-Swift code generator, written in Swift, and use it to generate
an HTTP client for the Storage API. Other Supabase services (Auth, PostgREST, ...) are
explicit follow-ups, not part of this effort.

This iteration produces the generator and generated code as real, compiling, tested
artifacts in the repo. It does **not** wire the generated client into the public
`SupabaseStorageClient` API — `StorageFileApi`, `StorageBucketApi`, and `Types.swift`
are untouched. Wiring is a separate future task once the generated shapes have been
reviewed.

## Background

- Storage does not currently publish a static OpenAPI document; it's produced on demand
  via `npm run docs:export` in the `supabase/storage` repo.
- [`supabase/storage#1215`](https://github.com/supabase/storage/pull/1215) fixes the
  spec for SDK generation: adds `operationId` to all operations (previously missing),
  registers `bucketSchema`/`objectSchema`/`authSchema`/`errorSchema` as named components
  instead of inlining them, renames the illegal `*` wildcard path param to `wildcard`,
  documents real 401/403 responses, dedupes trailing-slash duplicate paths, hides the
  schemaless S3-compatible catch-all route, and fixes three OpenAPI 3.1-only constructs
  (`type: [T, "null"]`, `anyOf` with a null branch, and a redundant top-level `anyOf` on
  `bucketUpdate`) that are invalid under the document's declared 3.0.3 version. That PR
  also confirms someone already ran `swift-openapi-generator` against this spec
  successfully after those fixes, which is independent validation that the fixed spec is
  well-formed OpenAPI 3.0.3.
- The Storage module today is 100% hand-written: no OpenAPI involved anywhere in this
  repo yet.
- A prior spike
  (`/Users/guilherme/src/github.com/grdsdev/spike-swift-supabase-code-generation`)
  evaluated `smithy-swift` and `swift-openapi-generator` for a similar generation problem
  and rejected both because their generated code mandates a runtime dependency
  (`ClientRuntime`/`OpenAPIRuntime`) and neither supports OS background sessions or
  upload progress — both hard requirements for Storage's large-file transfers. The spike
  hand-rolled a zero-dependency `HTTPRuntime` (streaming multipart-to-temp-file upload,
  streaming download, SSE, typed error decoding, upload/download progress via a delegate
  bridge) and a custom Node/TS emitter consuming Smithy/TypeSpec models directly (not
  OpenAPI) to preserve streaming fidelity that OpenAPI's schema loses.
- This effort reuses the spike's `HTTPRuntime` runtime and its "hand-roll the emitter,
  keep generated code dependency-free" conclusion, but swaps the source of truth to
  OpenAPI (since Storage already has one, once fixed) and the generator's implementation
  language to Swift (since this is a Swift-only repo and contributors shouldn't need a
  Node/JVM toolchain to regenerate the client).

## Architecture

```
supabase-swift/
  openapi/
    storage.json                  <- committed OpenAPI 3.0.3 doc (from storage#1215)
  tools/
    openapi-codegen/              <- own SPM package, own Package.swift
      Package.swift               <-   depends on OpenAPIKit30 (build-time only)
      Sources/openapi-codegen/
        main.swift                <-   CLI entry point
        IR.swift                  <-   internal model: operations, schemas, params
        OpenAPIParsing.swift      <-   OpenAPIKit30 doc -> IR
        SwiftEmitter.swift        <-   IR -> Swift source text
    node/                         <- existing cspell tooling (precedent for this layout)
  Sources/
    HTTPRuntime/                  <- copied from the spike, unmodified behavior
    StorageOpenAPI/               <- generated output, committed
      Models.swift
      StorageOpenAPIClient.swift
  Tests/
    StorageOpenAPITests/          <- Swift Testing, proves the generated client works
  Package.swift                   <- adds HTTPRuntime + StorageOpenAPI internal targets
```

### Why a separate nested package for the tool

`tools/openapi-codegen` gets its own `Package.swift` so `OpenAPIKit30` (and any other
codegen-only dependency) never appears in the main package's `Package.resolved`. Every
consumer of `supabase-swift` as a library resolves only the main `Package.swift`; the
codegen tool is invoked manually by maintainers and never built as part of a consumer's
dependency graph. This mirrors `tools/node`, which already isolates the cspell tooling
from the main package for the same reason.

### Why OpenAPIKit instead of hand-rolling the parser

The spike's "hand-roll everything" conclusion applied to the *emitter*, driven by the
requirement to preserve streaming fidelity that OpenAPI's schema loses when the source of
truth is TypeSpec/Smithy. Here the source of truth **is** OpenAPI, so that argument
doesn't transfer to the parsing layer: OpenAPIKit is a mature, MIT-licensed, actively
maintained library purpose-built for parsing and modeling OpenAPI documents (including
`$ref` resolution, JSON Schema nullable/enum/array handling) — it's the same library
`swift-openapi-generator` itself uses internally. Reimplementing that would be
redundant, error-prone effort spent on a solved problem. The custom, genuinely novel part
of this tool is the **emitter** — turning parsed operations/schemas into Swift that
targets `HTTPRuntime` instead of a shipped runtime dependency — and that's where the
implementation effort goes.

Apple's own `_OpenAPIGeneratorCore` (which also wraps OpenAPIKit) was considered and
rejected: it's underscore-prefixed specifically to signal "not for external use," with no
API stability guarantee — too risky to build a maintained tool on top of.

### Pipeline

1. `openapi-codegen` parses `openapi/storage.json` via `OpenAPIKit30.OpenAPI.Document`.
2. Builds an internal IR (operations with method/path/params/request-body/responses;
   schemas as structs/enums) decoupled from OpenAPIKit's types, so the emitter is simple
   and independently testable.
3. Emits two files into the target output directory:
   - `Models.swift` — `Codable, Sendable, Hashable` structs/enums from
     `components.schemas`.
   - `StorageOpenAPIClient.swift` — one `Sendable` struct with one `async throws` method
     per operation, built on `HTTPRequestBuilder`/`HTTPTransport` from `HTTPRuntime`,
     matching the shape already proven in the spike's generated clients (see
     `SpikeServiceClient.swift` for the target style: builder-based request assembly,
     `transport.send`/`transport.stream`, `response.checkStatus(errorTypes:)` for typed
     per-status errors).
4. CLI is generic, not Storage-specific: `openapi-codegen --spec <path> --output <dir>
   --module <name>`, so pointing it at a different service's spec later is a flag change,
   not a rewrite.

### Naming convention

Generated names mirror the spec verbatim: `operationId` → method name (e.g.
`createObject`), schema name → type name (e.g. `ObjectSchema`). No attempt is made to
match the hand-written API's naming (`upload`, `FileObject`) or shape. Reconciling the two
— deciding whether the public API adopts generated names, wraps them, or something else —
is deferred to the future wiring task, once the generated shapes exist to evaluate against.

### Emitter feature scope

Supported (validated against what's actually in Storage's fixed spec):
primitives/objects/arrays, string enums (`enum:` keyword), `nullable: true`, path/query/
header parameters, JSON request/response bodies, `multipart/form-data` request bodies
(emitted to stream via `HTTPRuntime`'s temp-file assembly, not buffered in memory), binary
response bodies, and per-status-code typed error responses (via `errorSchema`).

Unsupported constructs (a `oneOf`/`anyOf` discriminated union, an external `$ref`, a
`callbacks`/`links` object) make the generator **fail fast** with a diagnostic naming the
offending schema and its location in the document — never a silent best-effort guess at
unfamiliar shapes. Storage's fixed spec is not expected to contain any of these (PR #1215
specifically removes the one remaining `anyOf`), so this is a safety net, not an expected
code path for this run.

### Runtime

`Sources/HTTPRuntime/` is a verbatim copy of the spike's runtime (updated only for this
repo's file-header convention), added as an internal SPM target — not exported via
`@_exported import Supabase`, not a public product yet. It provides: buffered request/
response, streaming download, streaming multipart upload assembled onto a temp file
(constant memory), upload/download progress via a per-task delegate, and typed-error
decoding. None of this is exercised by real traffic in this iteration beyond what the
tests below cover — background-session support remains a design-only follow-up, matching
the spike's own conclusion.

### Testing

`Tests/StorageOpenAPITests/` (Swift Testing, per this repo's convention for new test
files) covers a handful of representative operations end-to-end against a mocked
transport — not all ~60 operations. At minimum: a bucket CRUD round-trip (JSON body,
typed response), an object upload (multipart request body), and a typed-error decode path
(e.g. a 404 on a missing bucket). The goal is proving the generated code is correct and
usable, not exhaustive spec coverage.

## Out of scope for this iteration

- Wiring generated code into `SupabaseStorageClient`/`StorageFileApi`/`StorageBucketApi`.
- Auth/`apikey` header injection or any other request customization needed for real use.
- OS background `URLSession` support (design-only, per the spike's own conclusion).
- Any spec besides Storage.
