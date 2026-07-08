# Storage OpenAPI Generator Adoption (Milestones 1–2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-written request/response plumbing in `StorageBucketApi` with a
generated OpenAPI client (from `swift-openapi-generator`), sourced from
[supabase/storage#1215](https://github.com/supabase/storage/pull/1215)'s spec, with zero public
API or behavior change.

**Architecture:** Vendor the spec, generate `Types.swift`/`Client.swift` once and commit them.
Add a small `StorageOpenAPITransport` that bridges the generated client's HTTP layer onto the
existing `execute()` request pipeline (same header merging, same `StorageError` decoding, same
`StorageHTTPSession` injection point — no behavior change). Migrate each `StorageBucketApi`
method one at a time to call the generated client internally while keeping its public signature
identical.

**Tech Stack:** Swift 6.1, `apple/swift-openapi-generator` (dev-only codegen tool, not a runtime
dependency), `apple/swift-openapi-runtime` (runtime dependency, ships to consumers), XCTest +
Mocker (existing test infra, unchanged).

**Design doc:** `docs/superpowers/specs/2026-07-08-storage-openapi-generator-design.md`

## Global Constraints

- No public API signature, type, or observable HTTP behavior may change. Every existing test in
  `Tests/StorageTests/StorageBucketAPITests.swift` must keep passing after each migration task,
  **except** where a test asserts the exact serialized JSON body of a request — those may need
  their snapshot re-recorded (see Task 9/10 note) because the generated client's JSON encoder
  doesn't necessarily preserve `configuration.encoder`'s `.sortedKeys` key ordering. The
  `Content-Length` byte count must stay the same (same keys/values, just possibly reordered).
- `apple/swift-openapi-generator` must NOT be added to the root `Package.swift` — it's a dev-only
  tool, isolated in `tools/openapi-generator`, following the existing `tools/node` precedent
  (`tools/node/package.json`, used for cspell).
- `apple/swift-openapi-runtime` IS added to the root `Package.swift` as a real dependency of the
  `Storage` target — the generated code imports `OpenAPIRuntime` at runtime.
- Run `./scripts/format.sh` before every commit that touches hand-written Swift files (not the
  generated ones — see Task 2).
- Platforms: iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+ (per `AGENTS.md`) — `URL`,
  `URLComponents` APIs used below are all available on these minimums.

---

### Task 1: Vendor the OpenAPI spec from PR #1215

**Files:**
- Create: `Sources/Storage/OpenAPI/openapi.json`
- Create: `Sources/Storage/OpenAPI/openapi-generator-config.yaml`

**Interfaces:**
- Produces: `Sources/Storage/OpenAPI/openapi.json` (OpenAPI 3.0.3 document, 25 paths under this
  config, includes `bucketSchema`/`objectSchema`/`errorSchema`/`authSchema` components and
  `bearerAuth` security scheme) — consumed by Task 2's codegen step.

- [ ] **Step 1: Export the spec from the storage PR branch**

Run (from any scratch directory, not this repo):

```bash
git clone https://github.com/supabase/storage.git /tmp/storage-pr-1215
cd /tmp/storage-pr-1215
gh pr checkout 1215
npm ci
PGRST_JWT_SECRET=dummydummydummydummydummydummy \
AUTH_JWT_SECRET=dummydummydummydummydummydummy \
ANON_KEY=dummy SERVICE_KEY=dummy \
DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres \
TENANT_ID=dummy STORAGE_BACKEND=file FILE_STORAGE_BACKEND_PATH=/tmp/storage \
FILE_SIZE_LIMIT=1000000 REGION=local GLOBAL_S3_BUCKET=dummy \
npm run docs:export
```

Expected: `static/api.json` is created (25 paths, no errors printed).

- [ ] **Step 2: Copy the spec into this repo**

```bash
cp /tmp/storage-pr-1215/static/api.json Sources/Storage/OpenAPI/openapi.json
rm -rf /tmp/storage-pr-1215
```

- [ ] **Step 3: Add the generator config**

Create `Sources/Storage/OpenAPI/openapi-generator-config.yaml`:

```yaml
generate:
  - types
  - client
accessModifier: internal
```

- [ ] **Step 4: Verify the spec is valid JSON and has the expected shape**

```bash
python3 -c "
import json
d = json.load(open('Sources/Storage/OpenAPI/openapi.json'))
assert d['openapi'] == '3.0.3'
assert 'bucketSchema' in d['components']['schemas']
assert 'objectSchema' in d['components']['schemas']
assert 'errorSchema' in d['components']['schemas']
print('OK:', len(d['paths']), 'paths')
"
```

Expected: `OK: 25 paths` (or more, if run against a merged/updated spec — that's fine).

- [ ] **Step 5: Commit**

```bash
git add Sources/Storage/OpenAPI/openapi.json Sources/Storage/OpenAPI/openapi-generator-config.yaml
git commit -m "feat(storage): vendor OpenAPI spec from supabase/storage#1215"
```

---

### Task 2: Codegen tooling — generate and commit the client

**Files:**
- Create: `tools/openapi-generator/Package.swift`
- Create: `scripts/generate-storage-openapi.sh`
- Create: `Sources/Storage/Generated/Types.swift` (generated output, do not hand-edit)
- Create: `Sources/Storage/Generated/Client.swift` (generated output, do not hand-edit)
- Modify: `Package.swift` (add `swift-openapi-runtime` dependency + `Storage` target dependency)

**Interfaces:**
- Produces: `Sources/Storage/Generated/{Types,Client}.swift`, importable as `OpenAPIRuntime`-backed
  `Components.Schemas.*`, `Operations.*`, and a `Client` type with one async throwing method per
  operation (e.g. `Client.bucketList(_:) async throws -> Operations.bucketList.Output`). Consumed
  by Task 4 onward.

- [ ] **Step 1: Add the isolated codegen tool package**

Create `tools/openapi-generator/Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "openapi-generator",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.5.0")
  ],
  targets: []
)
```

- [ ] **Step 2: Add the generation script**

Create `scripts/generate-storage-openapi.sh`:

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift run --package-path tools/openapi-generator swift-openapi-generator generate \
  Sources/Storage/OpenAPI/openapi.json \
  --config Sources/Storage/OpenAPI/openapi-generator-config.yaml \
  --output-directory Sources/Storage/Generated
```

```bash
chmod +x scripts/generate-storage-openapi.sh
```

- [ ] **Step 3: Add `swift-openapi-runtime` as a real dependency**

In the root `Package.swift`, add to the `dependencies:` array (after the `Mocker` line at
`Package.swift:32`):

```swift
    .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.6.0"),
```

Add to the `Storage` target's `dependencies:` (`Package.swift:169-173`):

```swift
    .target(
      name: "Storage",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
        "Helpers",
      ]
    ),
```

- [ ] **Step 4: Run codegen**

```bash
./scripts/generate-storage-openapi.sh
```

Expected: `Sources/Storage/Generated/Types.swift` and `Sources/Storage/Generated/Client.swift`
are created. This may take a minute or two the first time (resolves and builds the generator
executable).

- [ ] **Step 5: Inspect the generated `bucketSchema` type**

```bash
grep -n "struct bucketSchema" -A 30 Sources/Storage/Generated/Types.swift
```

Confirm it has `id: Swift.String`, `name: Swift.String`, and a property for the JSON `public`
field (escaped somehow, e.g. `` `public`: Swift.Bool? `` or `_public: Swift.Bool?` — note the
exact spelling found here; Task 6 depends on it). Also note the exact spelling of the
`file_size_limit` property (should be a plain `Swift.Int?`, not an enum, since the response
schema declares it as `type: ["null", "integer"]`).

- [ ] **Step 6: Verify the package builds**

```bash
swift build --target Storage
```

Expected: builds successfully (the generated code isn't used anywhere yet, so this just proves
the new dependency and generated sources compile standalone).

- [ ] **Step 7: Commit**

```bash
git add tools/openapi-generator scripts/generate-storage-openapi.sh Package.swift \
  Package.resolved Sources/Storage/Generated
git commit -m "feat(storage): generate OpenAPI client from vendored spec"
```

---

### Task 3: `StorageOpenAPITransport` + unit tests

**Files:**
- Create: `Sources/Storage/OpenAPI/StorageOpenAPITransport.swift`
- Test: `Tests/StorageTests/StorageOpenAPITransportTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks except the `OpenAPIRuntime` module (Task 2).
- Produces: `struct StorageOpenAPITransport: ClientTransport` with
  `init(execute: @escaping @Sendable (Helpers.HTTPRequest) async throws -> Helpers.HTTPResponse)`.
  Consumed by Task 4.

- [ ] **Step 1: Write the failing test**

Create `Tests/StorageTests/StorageOpenAPITransportTests.swift`:

```swift
import HTTPTypes
import OpenAPIRuntime
import XCTest

@testable import Storage

final class StorageOpenAPITransportTests: XCTestCase {
  func testSendJoinsBaseURLAndPathAndQuery() async throws {
    var capturedRequest: Helpers.HTTPRequest?

    let transport = StorageOpenAPITransport(execute: { request in
      capturedRequest = request
      return Helpers.HTTPResponse(
        data: Data(#"{"ok":true}"#.utf8),
        response: HTTPURLResponse(
          url: URL(string: "http://localhost/storage/v1/bucket")!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    })

    let (response, body) = try await transport.send(
      HTTPTypes.HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/bucket?limit=10"),
      body: nil,
      baseURL: URL(string: "http://localhost/storage/v1")!,
      operationID: "bucketList"
    )

    XCTAssertEqual(capturedRequest?.url.absoluteString, "http://localhost/storage/v1/bucket?limit=10")
    XCTAssertEqual(capturedRequest?.method, .get)
    XCTAssertEqual(response.status.code, 200)
    let data = try await Data(collecting: body ?? HTTPBody(""), upTo: .max)
    XCTAssertEqual(data, Data(#"{"ok":true}"#.utf8))
  }

  func testSendPropagatesBodyBytes() async throws {
    var capturedRequest: Helpers.HTTPRequest?

    let transport = StorageOpenAPITransport(execute: { request in
      capturedRequest = request
      return Helpers.HTTPResponse(
        data: Data(),
        response: HTTPURLResponse(
          url: URL(string: "http://localhost/storage/v1/bucket")!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    })

    _ = try await transport.send(
      HTTPTypes.HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/bucket"),
      body: HTTPBody(#"{"name":"avatars"}"#),
      baseURL: URL(string: "http://localhost/storage/v1")!,
      operationID: "bucketCreate"
    )

    XCTAssertEqual(capturedRequest?.body, Data(#"{"name":"avatars"}"#.utf8))
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter StorageOpenAPITransportTests
```

Expected: FAIL — `StorageOpenAPITransport` does not exist yet (compile error).

- [ ] **Step 3: Write the implementation**

Create `Sources/Storage/OpenAPI/StorageOpenAPITransport.swift`:

```swift
import Foundation
import HTTPTypes
import OpenAPIRuntime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Bridges the generated OpenAPI client's HTTP layer onto ``StorageApi``'s existing
/// `execute(_:)` pipeline, so header merging, ``StorageError`` decoding, and the injectable
/// ``StorageHTTPSession`` all keep working unchanged for OpenAPI-routed requests.
struct StorageOpenAPITransport: ClientTransport {
  var execute: @Sendable (Helpers.HTTPRequest) async throws -> Helpers.HTTPResponse

  func send(
    _ request: HTTPTypes.HTTPRequest,
    body: OpenAPIRuntime.HTTPBody?,
    baseURL: URL,
    operationID: String
  ) async throws -> (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?) {
    let requestTarget = request.path ?? ""
    let pathAndQuery = requestTarget.split(separator: "?", maxSplits: 1)
    let path = String(pathAndQuery.first ?? "")
    let query = pathAndQuery.count > 1 ? String(pathAndQuery[1]) : nil

    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw StorageOpenAPITransportError.invalidBaseURL(baseURL)
    }
    components.percentEncodedPath += path
    components.percentEncodedQuery = query

    guard let url = components.url else {
      throw StorageOpenAPITransportError.invalidRequestURL(path: requestTarget, baseURL: baseURL)
    }

    let requestBody: Data?
    if let body {
      requestBody = try await Data(collecting: body, upTo: .max)
    } else {
      requestBody = nil
    }

    var headers = HTTPFields()
    for field in request.headerFields {
      headers[field.name] = field.value
    }

    let helpersRequest = Helpers.HTTPRequest(
      url: url,
      method: request.method,
      headers: headers,
      body: requestBody
    )

    let response = try await execute(helpersRequest)

    let responseBody: OpenAPIRuntime.HTTPBody? =
      response.data.isEmpty ? nil : OpenAPIRuntime.HTTPBody(response.data)

    return (
      HTTPTypes.HTTPResponse(status: .init(code: response.statusCode)),
      responseBody
    )
  }
}

enum StorageOpenAPITransportError: Error {
  case invalidBaseURL(URL)
  case invalidRequestURL(path: String, baseURL: URL)
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter StorageOpenAPITransportTests
```

Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Storage/OpenAPI/StorageOpenAPITransport.swift \
  Tests/StorageTests/StorageOpenAPITransportTests.swift
git commit -m "feat(storage): add StorageOpenAPITransport bridging generated client to execute()"
```

---

### Task 4: Wire the generated `Client` into `StorageApi`

**Files:**
- Modify: `Sources/Storage/StorageApi.swift`

**Interfaces:**
- Consumes: `StorageOpenAPITransport` (Task 3), generated `Client` (Task 2).
- Produces: `StorageApi.openAPIClient: Client` (internal, accessible to subclasses
  `StorageBucketApi`/`StorageFileApi` in later tasks) and
  `StorageApi.executeRequest(_:headers:http:decoder:) async throws -> Helpers.HTTPResponse`
  (a `static` helper factoring out `execute(_:)`'s logic, reused by both `execute(_:)` itself and
  the transport closure — no self-capture-before-init issue).

- [ ] **Step 1: Write the failing test**

Add to `Tests/StorageTests/StorageBucketAPITests.swift` (after `tearDown`, before
`testURLConstruction`):

```swift
  func testOpenAPIClientUsesConfiguredBaseURLAndHeaders() async throws {
    Mock(
      url: url.appendingPathComponent("bucket/bucket123"),
      statusCode: 200,
      data: [
        .get: Data(
          """
          {
              "id": "bucket123",
              "name": "test-bucket",
              "owner": "owner123",
              "public": false,
              "created_at": "2024-01-01T00:00:00.000Z",
              "updated_at": "2024-01-01T00:00:00.000Z"
          }
          """.utf8
        )
      ]
    )
    .register()

    let output = try await storage.openAPIClient.bucketGet(
      .init(path: .init(bucketId: "bucket123"))
    )
    guard case .ok(let okResponse) = output, case .json(let bucket) = okResponse.body else {
      return XCTFail("expected .ok(.json) response")
    }
    XCTAssertEqual(bucket.id, "bucket123")
  }
```

`storage` here is the `SupabaseStorageClient` built in `setUp()`. `SupabaseStorageClient` inherits
from `StorageBucketApi` which inherits from `StorageApi`, so `storage.openAPIClient` must resolve
once this task adds the property.

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter StorageBucketAPITests/testOpenAPIClientUsesConfiguredBaseURLAndHeaders
```

Expected: FAIL — `value of type 'SupabaseStorageClient' has no member 'openAPIClient'`.

- [ ] **Step 3: Implement**

In `Sources/Storage/StorageApi.swift`, add the import at the top (after `import HTTPTypes` at
line 3):

```swift
import OpenAPIRuntime
```

Replace the `execute(_:)` method (`StorageApi.swift:107-127`) with a static helper plus a thin
instance wrapper, and add the `openAPIClient` property. The class becomes:

```swift
public class StorageApi: @unchecked Sendable {
  /// The configuration used to initialize this client instance.
  public let configuration: StorageClientConfiguration

  /// The generated OpenAPI client for the Storage HTTP API. Internal implementation detail —
  /// ``StorageBucketApi``/``StorageFileApi`` use this instead of hand-building requests.
  let openAPIClient: Client

  private struct MutableState {
    var headers: [String: String]
  }

  private let mutableState: LockIsolated<MutableState>
  private let http: any HTTPClientType

  public init(configuration: StorageClientConfiguration) {
    var configuration = configuration
    if configuration.headers["X-Client-Info"] == nil {
      configuration.headers["X-Client-Info"] = "storage-swift/\(version)"
    }

    if configuration.useNewHostname == true {
      guard
        var components = URLComponents(url: configuration.url, resolvingAgainstBaseURL: false),
        let host = components.host
      else {
        fatalError("Client initialized with invalid URL: \(configuration.url)")
      }

      let regex = try! NSRegularExpression(pattern: "supabase.(co|in|red)$")

      let isSupabaseHost =
        regex.firstMatch(in: host, range: NSRange(location: 0, length: host.utf16.count)) != nil

      if isSupabaseHost, !host.contains("storage.supabase.") {
        components.host = host.replacingOccurrences(of: "supabase.", with: "storage.supabase.")
      }

      configuration.url = components.url!
    }

    let initialHeaders = configuration.headers
    self.configuration = configuration
    self.mutableState = LockIsolated(MutableState(headers: initialHeaders))

    var interceptors: [any HTTPClientInterceptor] = []
    if let logger = configuration.logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    http = HTTPClient(
      fetch: configuration.session.fetch,
      interceptors: interceptors
    )

    let mutableStateRef = mutableState
    let httpRef = http
    let decoder = configuration.decoder
    openAPIClient = Client(
      serverURL: configuration.url,
      transport: StorageOpenAPITransport(execute: { request in
        try await Self.executeRequest(
          request, headers: mutableStateRef.headers, http: httpRef, decoder: decoder)
      })
    )
  }

  @discardableResult
  public func setHeader(_ value: String, forKey key: String) -> Self {
    mutableState.withValue { $0.headers[key.lowercased()] = value }
    return self
  }

  private static func executeRequest(
    _ request: Helpers.HTTPRequest,
    headers: [String: String],
    http: any HTTPClientType,
    decoder: JSONDecoder
  ) async throws -> Helpers.HTTPResponse {
    var request = request
    request.headers = HTTPFields(headers).merging(with: request.headers)

    let response = try await http.send(request)

    guard (200..<300).contains(response.statusCode) else {
      if let error = try? decoder.decode(StorageError.self, from: response.data) {
        throw error
      }
      throw HTTPError(data: response.data, response: response.underlyingResponse)
    }

    return response
  }

  @discardableResult
  func execute(_ request: Helpers.HTTPRequest) async throws -> Helpers.HTTPResponse {
    try await Self.executeRequest(
      request, headers: mutableState.headers, http: http, decoder: configuration.decoder)
  }
}
```

Leave the `extension Helpers.HTTPRequest { init(url:method:query:formData:options:headers:) }` at
the bottom of the file (`StorageApi.swift:130-154`) unchanged.

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter StorageBucketAPITests
```

Expected: PASS (all existing `StorageBucketAPITests` tests still pass, plus the new
`testOpenAPIClientUsesConfiguredBaseURLAndHeaders`).

- [ ] **Step 5: Format and commit**

```bash
./scripts/format.sh Sources/Storage/StorageApi.swift Tests/StorageTests/StorageBucketAPITests.swift
git add Sources/Storage/StorageApi.swift Tests/StorageTests/StorageBucketAPITests.swift
git commit -m "feat(storage): wire generated OpenAPI client onto StorageApi"
```

---

### Task 5: Migrate `listBuckets()`

**Files:**
- Modify: `Sources/Storage/StorageBucketApi.swift:37-45`

**Interfaces:**
- Consumes: `openAPIClient.bucketList(_:) async throws -> Operations.bucketList.Output` (Task 4),
  `Components.Schemas.bucketSchema` (Task 2).
- Produces: `Bucket(fromGenerated:)` — a `Bucket` initializer used by this and later bucket-read
  migrations (Task 6).

- [ ] **Step 1: Confirm the existing test still describes the desired behavior**

`Tests/StorageTests/StorageBucketAPITests.swift:148` (`testListBuckets`) already asserts the
curl-equivalent request and the decoded result. No new test needed — this is a refactor with an
existing regression test as the acceptance gate.

```bash
swift test --filter StorageBucketAPITests/testListBuckets
```

Expected: PASS (current hand-written implementation).

- [ ] **Step 2: Add the `Bucket` ↔ generated-schema bridge**

In `Sources/Storage/Types.swift`, immediately after the `Bucket` struct's `CodingKeys` (after
`Types.swift:649`, before the `// MARK: - StorageByteCount` comment), add:

```swift
extension Bucket {
  init(fromGenerated bucket: Components.Schemas.bucketSchema) {
    self.init(
      id: bucket.id,
      name: bucket.name,
      owner: bucket.owner ?? "",
      isPublic: bucket.`public` ?? false,
      createdAt: bucket.created_at.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date(timeIntervalSince1970: 0),
      updatedAt: bucket.updated_at.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date(timeIntervalSince1970: 0),
      allowedMimeTypes: bucket.allowed_mime_types,
      fileSizeLimit: bucket.file_size_limit.map(Int64.init)
    )
  }
}
```

> Before writing this, run
> `grep -n "struct bucketSchema" -A 30 Sources/Storage/Generated/Types.swift` (from Task 2 Step
> 5) and use the *exact* property names/types found there — property names for `created_at`,
> `updated_at`, `owner`, `public`, `allowed_mime_types`, `file_size_limit` may be camelCased by
> the generator's default naming strategy (e.g. `createdAt` instead of `created_at`), and the
> reserved word `public` may be escaped as `` `public` `` or `_public`. Adjust the field
> references above to match what's actually generated; the compiler will flag any mismatch with
> a clear "has no member" error naming the real property.

- [ ] **Step 3: Migrate `listBuckets()`**

Replace `Sources/Storage/StorageBucketApi.swift:37-45`:

```swift
  public func listBuckets() async throws -> [Bucket] {
    let output = try await openAPIClient.bucketList(.init())
    guard case .ok(let response) = output, case .json(let buckets) = response.body else {
      throw StorageError(statusCode: nil, message: "Unexpected response from Storage API")
    }
    return buckets.map(Bucket.init(fromGenerated:))
  }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter StorageBucketAPITests/testListBuckets
```

Expected: PASS — same curl snapshot as before (GET request, no body, so no encoding differences
apply here).

- [ ] **Step 5: Format and commit**

```bash
./scripts/format.sh Sources/Storage/Types.swift Sources/Storage/StorageBucketApi.swift
swift test --filter StorageBucketAPITests
git add Sources/Storage/Types.swift Sources/Storage/StorageBucketApi.swift
git commit -m "refactor(storage): migrate listBuckets() to generated OpenAPI client"
```

---

### Task 6: Migrate `getBucket(_:)`

**Files:**
- Modify: `Sources/Storage/StorageBucketApi.swift:52-60`

**Interfaces:**
- Consumes: `openAPIClient.bucketGet(_:) async throws -> Operations.bucketGet.Output`,
  `Bucket.init(fromGenerated:)` (Task 5).

- [ ] **Step 1: Confirm the existing test describes the desired behavior**

```bash
swift test --filter StorageBucketAPITests/testGetBucket
```

Expected: PASS (current implementation).

- [ ] **Step 2: Migrate**

Replace `Sources/Storage/StorageBucketApi.swift:52-60`:

```swift
  public func getBucket(_ id: String) async throws -> Bucket {
    let output = try await openAPIClient.bucketGet(.init(path: .init(bucketId: id)))
    guard case .ok(let response) = output, case .json(let bucket) = response.body else {
      throw StorageError(statusCode: nil, message: "Unexpected response from Storage API")
    }
    return Bucket(fromGenerated: bucket)
  }
```

- [ ] **Step 3: Run test to verify it passes**

```bash
swift test --filter StorageBucketAPITests/testGetBucket
```

Expected: PASS, same curl snapshot as before.

- [ ] **Step 4: Format and commit**

```bash
./scripts/format.sh Sources/Storage/StorageBucketApi.swift
swift test --filter StorageBucketAPITests
git add Sources/Storage/StorageBucketApi.swift
git commit -m "refactor(storage): migrate getBucket(_:) to generated OpenAPI client"
```

---

### Task 7: Migrate `deleteBucket(_:)`

**Files:**
- Modify: `Sources/Storage/StorageBucketApi.swift:160-167`

**Interfaces:**
- Consumes: `openAPIClient.bucketDelete(_:) async throws -> Operations.bucketDelete.Output`.

- [ ] **Step 1: Confirm the existing test describes the desired behavior**

```bash
swift test --filter StorageBucketAPITests/testDeleteBucket
```

Expected: PASS.

- [ ] **Step 2: Migrate**

`deleteBucket` doesn't decode a body today (`async throws`, no return value), so the migration
only needs to confirm success:

```swift
  public func deleteBucket(_ id: String) async throws {
    let output = try await openAPIClient.bucketDelete(.init(path: .init(bucketId: id)))
    guard case .ok = output else {
      throw StorageError(statusCode: nil, message: "Unexpected response from Storage API")
    }
  }
```

- [ ] **Step 3: Run test to verify it passes**

```bash
swift test --filter StorageBucketAPITests/testDeleteBucket
```

Expected: PASS, same curl snapshot as before (DELETE, no body).

- [ ] **Step 4: Format and commit**

```bash
./scripts/format.sh Sources/Storage/StorageBucketApi.swift
swift test --filter StorageBucketAPITests
git add Sources/Storage/StorageBucketApi.swift
git commit -m "refactor(storage): migrate deleteBucket(_:) to generated OpenAPI client"
```

---

### Task 8: Migrate `emptyBucket(_:)`

**Files:**
- Modify: `Sources/Storage/StorageBucketApi.swift:143-150`

**Interfaces:**
- Consumes: `openAPIClient.bucketEmpty(_:) async throws -> Operations.bucketEmpty.Output`.

- [ ] **Step 1: Confirm the existing test describes the desired behavior**

```bash
swift test --filter StorageBucketAPITests/testEmptyBucket
```

Expected: PASS.

- [ ] **Step 2: Migrate**

```swift
  public func emptyBucket(_ id: String) async throws {
    let output = try await openAPIClient.bucketEmpty(.init(path: .init(bucketId: id)))
    guard case .ok = output else {
      throw StorageError(statusCode: nil, message: "Unexpected response from Storage API")
    }
  }
```

- [ ] **Step 3: Run test to verify it passes**

```bash
swift test --filter StorageBucketAPITests/testEmptyBucket
```

Expected: PASS, same curl snapshot as before (POST, no body).

- [ ] **Step 4: Format and commit**

```bash
./scripts/format.sh Sources/Storage/StorageBucketApi.swift
swift test --filter StorageBucketAPITests
git add Sources/Storage/StorageBucketApi.swift
git commit -m "refactor(storage): migrate emptyBucket(_:) to generated OpenAPI client"
```

---

### Task 9: Migrate `createBucket(_:options:)`

**Files:**
- Modify: `Sources/Storage/StorageBucketApi.swift:70-103`
- Test: `Tests/StorageTests/StorageBucketAPITests.swift:184-222,308-383` (re-record snapshots)

**Interfaces:**
- Consumes: `openAPIClient.bucketCreate(_:) async throws -> Operations.bucketCreate.Output`,
  `Operations.bucketCreate.Input.Body.jsonPayload` (the request body's anyOf `file_size_limit`
  needs inspection — see Step 1).

- [ ] **Step 1: Inspect the generated request body type**

```bash
grep -n "enum bucketCreate" -A 5 Sources/Storage/Generated/Types.swift
grep -n "struct Body" -A 20 Sources/Storage/Generated/Types.swift | grep -A 20 "bucketCreate" 
grep -n "jsonPayload" -A 15 Sources/Storage/Generated/Types.swift | head -60
```

Find the exact synthesized type for the request body (expected:
`Operations.bucketCreate.Input.Body.jsonPayload` with properties `name: Swift.String`,
`id: Swift.String?`, `public: Swift.Bool?` (name possibly escaped), `file_size_limit` typed as an
enum wrapping `Swift.Int` and `Swift.String` cases (since the spec declares
`anyOf: [integer, string]` for this field) — note the exact case names (e.g. `.case1`/`.case2`,
or generator-synthesized names). `BucketOptions.fileSizeLimit` (`Types.swift:965`) is already
always a `String?` by the time it reaches `StorageBucketApi`, so only the **string** case of
that enum is ever needed here.

- [ ] **Step 2: Migrate**

Replace `Sources/Storage/StorageBucketApi.swift:70-103` (keep the `BucketParameters` struct at
lines 62-68 removed as part of Task 11's cleanup, not here — other call sites still use it until
Task 10 migrates `updateBucket`):

```swift
  public func createBucket(_ id: String, options: BucketOptions = BucketOptions(isPublic: false))
    async throws
  {
    let output = try await openAPIClient.bucketCreate(
      .init(
        body: .json(
          .init(
            name: id,
            id: id,
            `public`: options.isPublic,
            file_size_limit: options.fileSizeLimit.map { .case2($0) },
            allowed_mime_types: options.allowedMimeTypes
          )
        )
      )
    )
    guard case .ok = output else {
      throw StorageError(statusCode: nil, message: "Unexpected response from Storage API")
    }
  }
```

> Use the exact property names and the exact `file_size_limit` enum case name found in Step 1.
> If the generated property for `public` is escaped differently (e.g. `_public`), or the
> enum case for the string variant isn't `.case2`, the compiler error at this call site will name
> the actual member — fix the reference to match.

- [ ] **Step 3: Run the existing tests and re-record snapshots**

```bash
swift test --filter StorageBucketAPITests/testCreateBucket
swift test --filter StorageBucketAPITests/testCreateBucketWithFileSizeLimit
swift test --filter StorageBucketAPITests/testCreateBucketWithHumanReadableFileSizeLimit
```

Expected: these may FAIL on the `--data` line of the snapshot if the generated client's JSON
encoder orders keys differently than `configuration.encoder`'s `.sortedKeys`. If so:

1. Confirm the failure is *only* a key-order difference (same keys, same values, same total
   `Content-Length`) — inspect the diff `InlineSnapshotTesting` prints.
2. Re-record by running with `--record` (this repo's snapshot tests use
   `InlineSnapshotTesting`/`swift-snapshot-testing`; if failures show a suggested replacement
   literal, apply it directly to the test file, or run
   `SNAPSHOT_TESTING_RECORD=all swift test --filter StorageBucketAPITests/testCreateBucket` and
   confirm the tool updates the inline `--data` string in place).
3. Re-run the three tests above to confirm they now pass with the re-recorded snapshot.

If the `Content-Length` byte count changed, or a key/value is missing or different, STOP — this
means the request body isn't semantically equivalent, and the mapping in Step 2 needs fixing
before continuing.

- [ ] **Step 4: Format and commit**

```bash
./scripts/format.sh Sources/Storage/StorageBucketApi.swift Tests/StorageTests/StorageBucketAPITests.swift
swift test --filter StorageBucketAPITests
git add Sources/Storage/StorageBucketApi.swift Tests/StorageTests/StorageBucketAPITests.swift
git commit -m "refactor(storage): migrate createBucket(_:options:) to generated OpenAPI client"
```

---

### Task 10: Migrate `updateBucket(_:options:)`

**Files:**
- Modify: `Sources/Storage/StorageBucketApi.swift:118-134`
- Test: `Tests/StorageTests/StorageBucketAPITests.swift:224-262` (re-record snapshot if needed)

**Interfaces:**
- Consumes: `openAPIClient.bucketUpdate(_:) async throws -> Operations.bucketUpdate.Output`.

- [ ] **Step 1: Inspect the generated request body type**

```bash
grep -n "enum bucketUpdate" -A 5 Sources/Storage/Generated/Types.swift
grep -n "jsonPayload" -A 15 Sources/Storage/Generated/Types.swift | head -80
```

Same shape as `bucketCreate`'s body minus `name`/`id`/`type` (per the spec, `bucketUpdate`'s body
only has `public`, `file_size_limit`, `allowed_mime_types`, all optional).

- [ ] **Step 2: Migrate**

Replace `Sources/Storage/StorageBucketApi.swift:118-134`:

```swift
  public func updateBucket(_ id: String, options: BucketOptions) async throws {
    let output = try await openAPIClient.bucketUpdate(
      .init(
        path: .init(bucketId: id),
        body: .json(
          .init(
            `public`: options.isPublic,
            file_size_limit: options.fileSizeLimit.map { .case2($0) },
            allowed_mime_types: options.allowedMimeTypes
          )
        )
      )
    )
    guard case .ok = output else {
      throw StorageError(statusCode: nil, message: "Unexpected response from Storage API")
    }
  }
```

> As in Task 9, confirm the exact property/case names against
> `Sources/Storage/Generated/Types.swift` and adjust if the compiler flags a mismatch.

- [ ] **Step 3: Run the existing test and re-record the snapshot if needed**

```bash
swift test --filter StorageBucketAPITests/testUpdateBucket
```

Same procedure as Task 9 Step 3 if the `--data` snapshot fails on key order only.

- [ ] **Step 4: Format and commit**

```bash
./scripts/format.sh Sources/Storage/StorageBucketApi.swift Tests/StorageTests/StorageBucketAPITests.swift
swift test --filter StorageBucketAPITests
git add Sources/Storage/StorageBucketApi.swift Tests/StorageTests/StorageBucketAPITests.swift
git commit -m "refactor(storage): migrate updateBucket(_:options:) to generated OpenAPI client"
```

---

### Task 11: Remove dead code and run the full suite

**Files:**
- Modify: `Sources/Storage/StorageBucketApi.swift` (remove the now-unused `BucketParameters`
  struct)

**Interfaces:**
- None — this is cleanup only.

- [ ] **Step 1: Confirm `BucketParameters` is unused**

```bash
grep -rn "BucketParameters" Sources/Storage Tests/StorageTests
```

Expected: only the struct definition itself remains (all six bucket methods were migrated in
Tasks 5–10).

- [ ] **Step 2: Remove it**

Delete the `BucketParameters` struct definition from `Sources/Storage/StorageBucketApi.swift`
(originally at lines 62-68).

- [ ] **Step 3: Run the full test suite**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild
```

Expected: all tests pass, including every test in `StorageBucketAPITests`,
`StorageOpenAPITransportTests`, and the rest of the existing suite (`StorageFileAPITests`,
`SupabaseStorageTests`, etc. — untouched by this plan, must show no regressions).

- [ ] **Step 4: Format everything touched by this plan**

```bash
./scripts/format.sh
git status
```

Expected: only files this plan touched show as modified (`Sources/Storage/*.swift`,
`Sources/Storage/OpenAPI/*`, `Sources/Storage/Generated/*`, `Tests/StorageTests/*`,
`Package.swift`, `Package.resolved`, `tools/openapi-generator/*`, `scripts/*`). If `format.sh`
reformats unrelated files, revert those with `git checkout -- <file>` — CI only format-checks
changed files.

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "refactor(storage): remove BucketParameters, superseded by generated OpenAPI client"
```

---

## What's next

Milestones 3 (JSON-only `StorageFileApi` operations) and 4 (multipart upload/update, binary
download) get their own follow-up plans once this one lands — the exact generated `Operations.*`
signatures for those endpoints should be verified against whatever spec is vendored at that time
(ideally the merged `master` version of supabase/storage#1215, per the design doc's rollout).
