# Storage OpenAPI Codegen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a generic Swift OpenAPI-to-Swift codegen tool and use it to generate an HTTP client for Storage, without wiring the generated code into the public `Storage` API yet.

**Architecture:** A standalone SPM package `tools/openapi-codegen` parses an OpenAPI 3.0.3 document with `OpenAPIKit30` into a small internal IR, then a hand-written emitter turns that IR into Swift source targeting a zero-dependency runtime (`HTTPRuntime`, copied verbatim from a prior spike) that lives in the main package. The tool is run manually against Storage's spec; its output is committed like any other source file.

**Tech Stack:** Swift 6.1, SPM, `OpenAPIKit30` (tool-only dependency), Swift Testing.

## Global Constraints

- `OpenAPIKit30` pinned to `from: "6.2.0"` in `tools/openapi-codegen/Package.swift` — this is the same library `swift-openapi-generator` uses internally to parse OpenAPI 3.0.x documents. If a symbol referenced below doesn't match the installed version, check that tag's source under `Sources/OpenAPIKit30/` before improvising a workaround.
- `tools/openapi-codegen` never becomes a dependency of the main `Package.swift` — it is invoked manually (`swift run --package-path tools/openapi-codegen openapi-codegen ...`), matching how `tools/node` (cspell) is isolated today.
- Generated Swift mirrors the OpenAPI spec verbatim: `operationId` → method name, schema name → type name. No attempt to match the hand-written `StorageFileApi`/`FileObject` naming.
- Unsupported OpenAPI constructs (`oneOf`/`anyOf`/`allOf`/`not`, external `$ref`, inline enums, inline object schemas with defined properties, cookie parameters, parameters using `content` instead of `schema`) make the generator **throw an error naming the offending location** — never a silent best-effort guess.
- `nullable: true` OR "not in the `required` list" both become `Optional` in emitted Swift — Swift's `Codable` doesn't distinguish "absent" from "explicit null" without custom decode logic, and this codebase doesn't need that distinction yet.
- New test files use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`) per this repo's convention — including the ported runtime tests, which existed as XCTest in the spike.
- For `tools/openapi-codegen` (a standalone SPM package, not part of `Supabase.xcworkspace`), use plain `swift test` — there's no Xcode scheme for it. For the main package's new targets (`HTTPRuntime`, `StorageOpenAPI`), use `swift test --filter <Target>` for fast iteration during a task, but the final gate in Task 15 is the full `xcodebuild` run this repo's contributors rely on (`PLATFORM=IOS XCODEBUILD_ARGUMENT=test ./scripts/xcodebuild.sh`), not `swift test`.
- Every Swift file added to the main package gets the standard header:
  ```swift
  //
  //  FileName.swift
  //  ModuleName
  //
  //  Created by Guilherme Souza on 08/07/26.
  //
  ```
- Run `./scripts/format.sh` on any file you touch in the main package before committing (per AGENTS.md); this is not required inside `tools/openapi-codegen` (separate package, not covered by this repo's format config).

---

## File Structure

```
supabase-swift/
  openapi/
    storage.json                              <- Task 12
  tools/openapi-codegen/
    Package.swift                             <- Task 2
    Sources/OpenAPICodegenCore/
      IR.swift                                <- Task 3
      OpenAPIParsing.swift                    <- Tasks 3-7
      SwiftNames.swift                        <- Task 8
      SwiftEmitter.swift                      <- Tasks 9-10
    Sources/openapi-codegen/
      main.swift                              <- Task 11
    Tests/OpenAPICodegenCoreTests/
      SchemaParsingTests.swift                <- Task 3
      TypeParsingTests.swift                  <- Task 4
      ParameterParsingTests.swift             <- Task 5
      RequestBodyParsingTests.swift           <- Task 6
      ResponseParsingTests.swift              <- Task 7
      SwiftNamesTests.swift                   <- Task 8
      ModelEmitterTests.swift                 <- Task 9
      ClientEmitterTests.swift                <- Task 10
    Tests/openapi-codegenTests/
      EndToEndTests.swift                     <- Task 11
  Sources/HTTPRuntime/                        <- Task 1 (copied from the spike, 11 files)
  Sources/StorageOpenAPI/
    Models.swift                              <- Task 13
    StorageOpenAPIClient.swift                <- Task 13
  Tests/HTTPRuntimeTests/
    HTTPRuntimeTests.swift                    <- Task 1
  Tests/StorageOpenAPITests/
    BucketOperationsTests.swift               <- Task 14
    ObjectUploadTests.swift                   <- Task 14
    ErrorDecodingTests.swift                  <- Task 14
  Package.swift                               <- Tasks 1, 13 (add HTTPRuntime + StorageOpenAPI targets)
```

---

### Task 1: Copy HTTPRuntime into the main package

**Files:**
- Create: `Sources/HTTPRuntime/HTTPError.swift`, `HTTPMethod.swift`, `HTTPRequest.swift`, `HTTPResponse.swift`, `HTTPTransport.swift`, `JSONCoding.swift`, `JSONValue.swift`, `MultipartFormData.swift`, `PathEncoding.swift`, `ServerSentEvents.swift`, `TransferProgress.swift`, `URLSessionTransport.swift`
- Create: `Tests/HTTPRuntimeTests/HTTPRuntimeTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Produces: `HTTPTransport` (protocol), `HTTPRequest`/`HTTPRequestBuilder`/`HTTPResponse`/`HTTPResponseStream`, `HTTPError`, `APIError` (protocol), `JSONCoding.encoder`/`.decoder`, `JSONValue`, `MultipartFormData`, `PathEncoding.segment(_:)`/`.greedy(_:)`, `URLSessionTransport` — all `public`, used by every later task.

- [ ] **Step 1: Copy the runtime files verbatim, then prepend this repo's file header**

```bash
cp /Users/guilherme/src/github.com/grdsdev/spike-swift-supabase-code-generation/Sources/HTTPRuntime/*.swift \
   Sources/HTTPRuntime/

for f in Sources/HTTPRuntime/*.swift; do
  name=$(basename "$f")
  header="//\n//  ${name}\n//  HTTPRuntime\n//\n//  Created by Guilherme Souza on 08/07/26.\n//\n"
  printf '%b\n%s' "$header" "$(cat "$f")" > "$f.tmp" && mv "$f.tmp" "$f"
done
```

- [ ] **Step 2: Register the `HTTPRuntime` target and test target in `Package.swift`**

Add this block to the `targets:` array, right after the `HelpersTests` target (both `HTTPRuntime` and `Helpers` are dependency-free foundations other targets build on):

```swift
    .target(
      name: "HTTPRuntime"
    ),
    .testTarget(
      name: "HTTPRuntimeTests",
      dependencies: [
        "HTTPRuntime"
      ]
    ),
```

Add `"HTTPRuntimeTests"` to the `swift6TestTargets` set near the bottom of the file:

```swift
let swift6TestTargets: Set<String> = ["SupabaseTests", "HelpersTests", "HTTPRuntimeTests"]
```

- [ ] **Step 3: Write the ported runtime tests (Swift Testing, not the spike's XCTest)**

```swift
//
//  HTTPRuntimeTests.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 08/07/26.
//

import Foundation
import Testing

@testable import HTTPRuntime

@Suite
struct HTTPRuntimeTests {

  @Test
  func serverSentEventParsing() async throws {
    let raw = """
      event: message
      data: {"delta":"hello"}

      event: progress
      data: {"percent":50}

      event: done
      data: {"total":3}


      """
    let bytes = AsyncThrowingStream<Data, any Error> { continuation in
      let full = Array(Data(raw.utf8))
      let mid = full.count / 2
      continuation.yield(Data(full[0..<mid]))
      continuation.yield(Data(full[mid...]))
      continuation.finish()
    }
    var events: [ServerSentEvent] = []
    for try await event in bytes.serverSentEvents() { events.append(event) }
    #expect(events.count == 3)
    #expect(events[0].event == "message")
    #expect(events[0].data == #"{"delta":"hello"}"#)
    #expect(events[1].event == "progress")
    #expect(events[2].event == "done")
  }

  @Test
  func serverSentEventMultiLineData() async throws {
    let raw = "data: line1\ndata: line2\n\n"
    let bytes = AsyncThrowingStream<Data, any Error> { continuation in
      continuation.yield(Data(raw.utf8))
      continuation.finish()
    }
    var events: [ServerSentEvent] = []
    for try await event in bytes.serverSentEvents() { events.append(event) }
    #expect(events.count == 1)
    #expect(events[0].data == "line1\nline2")
  }

  @Test
  func multipartAssemblesToFileWithoutBufferingSource() throws {
    let sourceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("src-\(UUID().uuidString).bin")
    let payload = Data((0..<200_000).map { UInt8($0 % 256) })
    try payload.write(to: sourceURL)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    var form = MultipartFormData(boundary: "TESTBOUNDARY")
    form.append(.init(name: "meta", source: .data(Data(#"{"k":"v"}"#.utf8))))
    form.append(
      .init(
        name: "file", filename: "big.bin", contentType: "application/octet-stream",
        source: .file(sourceURL)))

    let bodyURL = try form.writeToTemporaryFile()
    defer { try? FileManager.default.removeItem(at: bodyURL) }
    let body = try Data(contentsOf: bodyURL)

    #expect(form.contentType == "multipart/form-data; boundary=TESTBOUNDARY")
    let text = String(decoding: body.prefix(400), as: UTF8.self)
    #expect(text.contains("--TESTBOUNDARY"))
    #expect(text.contains(#"Content-Disposition: form-data; name="meta""#))
    #expect(text.contains(#"name="file"; filename="big.bin""#))
    #expect(body.count > payload.count)
  }

  @Test
  func pathEncoding() {
    #expect(PathEncoding.segment("a/b c") == "a%2Fb%20c")
    #expect(PathEncoding.greedy("a/b/c.txt") == "a/b/c.txt")
    #expect(PathEncoding.greedy("a/b c.txt") == "a/b%20c.txt")
  }

  @Test
  func jsonValueRoundTrip() throws {
    let value = JSONValue.object([
      "s": .string("x"),
      "n": .number(3.5),
      "b": .bool(true),
      "arr": .array([.number(1), .null]),
    ])
    let data = try JSONCoding.encoder.encode(value)
    let decoded = try JSONCoding.decoder.decode(JSONValue.self, from: data)
    #expect(decoded == value)
  }

  @Test
  func iso8601DateCoding() throws {
    struct Holder: Codable, Equatable { let at: Date }
    let json = #"{"at":"2026-07-06T12:34:56.789Z"}"#
    let decoded = try JSONCoding.decoder.decode(Holder.self, from: Data(json.utf8))
    let reencoded = try JSONCoding.encoder.encode(decoded)
    let round = try JSONCoding.decoder.decode(Holder.self, from: reencoded)
    #expect(decoded == round)
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter HTTPRuntimeTests`
Expected: PASS (6 tests)

- [ ] **Step 5: Format and commit**

```bash
./scripts/format.sh
git add Sources/HTTPRuntime Tests/HTTPRuntimeTests Package.swift
git commit -m "feat(runtime): copy zero-dependency HTTPRuntime from the codegen spike"
```

---

### Task 2: Scaffold the `tools/openapi-codegen` package

**Files:**
- Create: `tools/openapi-codegen/Package.swift`
- Create: `tools/openapi-codegen/Sources/OpenAPICodegenCore/IR.swift` (placeholder type, replaced fully in Task 3)
- Create: `tools/openapi-codegen/Sources/openapi-codegen/main.swift`

**Interfaces:**
- Produces: an `OpenAPICodegenCore` library target and an `openapi-codegen` executable target that later tasks add real code to.

- [ ] **Step 1: Write the package manifest**

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "openapi-codegen",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "openapi-codegen", targets: ["openapi-codegen"])
  ],
  dependencies: [
    .package(url: "https://github.com/mattpolzin/OpenAPIKit.git", from: "6.2.0")
  ],
  targets: [
    .target(
      name: "OpenAPICodegenCore",
      dependencies: [
        .product(name: "OpenAPIKit30", package: "OpenAPIKit")
      ]
    ),
    .executableTarget(
      name: "openapi-codegen",
      dependencies: ["OpenAPICodegenCore"]
    ),
    .testTarget(
      name: "OpenAPICodegenCoreTests",
      dependencies: ["OpenAPICodegenCore"]
    ),
    .testTarget(
      name: "openapi-codegenTests",
      dependencies: ["OpenAPICodegenCore"]
    ),
  ]
)
```

- [ ] **Step 2: Add a minimal `IR.swift` so the target compiles**

```swift
enum IRPlaceholder {}
```

- [ ] **Step 3: Add a minimal `main.swift`**

```swift
print("openapi-codegen: not yet implemented")
```

- [ ] **Step 4: Verify the package builds**

Run: `swift build --package-path tools/openapi-codegen`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add tools/openapi-codegen
git commit -m "chore(codegen): scaffold the openapi-codegen tool package"
```

---

### Task 3: IR types + schema parsing (objects, string enums)

**Files:**
- Modify: `tools/openapi-codegen/Sources/OpenAPICodegenCore/IR.swift` (replace placeholder)
- Create: `tools/openapi-codegen/Sources/OpenAPICodegenCore/OpenAPIParsing.swift`
- Create: `tools/openapi-codegen/Tests/OpenAPICodegenCoreTests/SchemaParsingTests.swift`

**Interfaces:**
- Consumes: `OpenAPIKit30.OpenAPI.Document`/`JSONSchema` (external dependency).
- Produces: `IRDocument`, `IRSchema`, `IRSchemaKind`, `IRProperty`, `IRType`, `UnsupportedSpecConstruct`, and `OpenAPIParsing.parseNamedSchema(name:schema:)` — all used by every later parsing/emitting task.

- [ ] **Step 1: Write the failing test**

```swift
//
//  SchemaParsingTests.swift
//

import OpenAPIKit30
import Testing

@testable import OpenAPICodegenCore

@Suite
struct SchemaParsingTests {

  @Test
  func parsesObjectSchemaWithRequiredAndOptionalProperties() throws {
    let json = """
      {
        "type": "object",
        "required": ["id"],
        "properties": {
          "id": {"type": "string"},
          "name": {"type": "string", "nullable": true},
          "size": {"type": "integer"}
        }
      }
      """
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    let irSchema = try OpenAPIParsing.parseNamedSchema(name: "widgetSchema", schema: schema)

    #expect(irSchema.name == "widgetSchema")
    guard case .object(let properties) = irSchema.kind else {
      Issue.record("expected an object schema")
      return
    }
    let byName = Dictionary(uniqueKeysWithValues: properties.map { ($0.name, $0) })
    #expect(byName["id"]?.type == .string)
    #expect(byName["id"]?.isOptional == false)
    #expect(byName["name"]?.isOptional == true)
    #expect(byName["size"]?.type == .integer)
    #expect(byName["size"]?.isOptional == true)
  }

  @Test
  func parsesStringEnumSchema() throws {
    let json = """
      {"type": "string", "enum": ["public", "private"]}
      """
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    let irSchema = try OpenAPIParsing.parseNamedSchema(name: "visibility", schema: schema)

    #expect(irSchema.name == "visibility")
    #expect(irSchema.kind == .stringEnum(cases: ["public", "private"]))
  }

  @Test
  func rejectsNonObjectNonEnumTopLevelSchema() throws {
    let json = #"{"type": "integer"}"#
    let schema = try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))

    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseNamedSchema(name: "count", schema: schema)
    }
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path tools/openapi-codegen --filter SchemaParsingTests`
Expected: FAIL to compile (`IRDocument`/`OpenAPIParsing` not defined)

- [ ] **Step 3: Write `IR.swift`**

```swift
//
//  IR.swift
//

/// Intermediate representation of an OpenAPI document, decoupled from
/// OpenAPIKit's types so the emitter doesn't need to know anything about
/// OpenAPI parsing.
struct IRDocument: Equatable {
  var schemas: [IRSchema]
  var operations: [IROperation]
}

struct IRSchema: Equatable {
  var name: String
  var kind: IRSchemaKind
}

enum IRSchemaKind: Equatable {
  case object(properties: [IRProperty])
  case stringEnum(cases: [String])
}

struct IRProperty: Equatable {
  var name: String
  var type: IRType
  var isOptional: Bool
}

indirect enum IRType: Equatable {
  case string
  case integer
  case number
  case boolean
  case array(IRType)
  case schemaRef(String)
  /// An object with no defined properties (OpenAPI's `{"type": "object"}` with
  /// no `properties`) — modeled as `[String: JSONValue]` in emitted Swift.
  case freeform
}

enum IRHTTPMethod: String, Equatable {
  case get, put, post, delete, options, head, patch, trace
}

enum IRParameterLocation: Equatable {
  case path, query, header
}

struct IRParameter: Equatable {
  var name: String
  var location: IRParameterLocation
  var type: IRType
  var isOptional: Bool
}

enum IRRequestBody: Equatable {
  case json(IRType)
  case multipart(fields: [IRMultipartField])
}

struct IRMultipartField: Equatable {
  var name: String
  var type: IRType
  var isFile: Bool
}

enum IRResponseBody: Equatable {
  case none
  case json(IRType)
  case binary
}

struct IRResponse: Equatable {
  var statusCode: Int
  var isError: Bool
  var body: IRResponseBody
}

struct IROperation: Equatable {
  var operationId: String
  var method: IRHTTPMethod
  var path: String
  var parameters: [IRParameter]
  var requestBody: IRRequestBody?
  var responses: [IRResponse]
}
```

- [ ] **Step 4: Write `OpenAPIParsing.swift` (schema parsing only for now)**

```swift
//
//  OpenAPIParsing.swift
//

import OpenAPIKit30

/// Thrown when the input spec uses a construct this generator deliberately
/// doesn't support (see the plan's Global Constraints for the full list).
/// Never guess at an unfamiliar shape — fail with the exact location instead.
struct UnsupportedSpecConstruct: Error, CustomStringConvertible, Equatable {
  var location: String
  var reason: String

  var description: String { "Unsupported OpenAPI construct at \(location): \(reason)" }
}

enum OpenAPIParsing {

  // MARK: - Schemas

  static func parseNamedSchema(name: String, schema: JSONSchema) throws -> IRSchema {
    if case .string = schema.value, let allowedValues = schema.allowedValues {
      let cases = allowedValues.compactMap { $0.value as? String }
      return IRSchema(name: name, kind: .stringEnum(cases: cases))
    }
    guard case .object(_, let objectContext) = schema.value else {
      throw UnsupportedSpecConstruct(
        location: "components.schemas.\(name)",
        reason: "top-level schema must be an object or a string enum"
      )
    }
    var properties: [IRProperty] = []
    for (propertyName, propertySchema) in objectContext.properties {
      properties.append(
        IRProperty(
          name: propertyName,
          type: try parseType(propertySchema, location: "\(name).\(propertyName)"),
          isOptional: !propertySchema.required || propertySchema.nullable
        )
      )
    }
    return IRSchema(name: name, kind: .object(properties: properties))
  }

  static func parseType(_ schema: JSONSchema, location: String) throws -> IRType {
    if case .string = schema.value, schema.allowedValues != nil {
      throw UnsupportedSpecConstruct(
        location: location,
        reason: "inline enum; register it as a named component schema instead"
      )
    }
    switch schema.value {
    case .string:
      return .string
    case .integer:
      return .integer
    case .number:
      return .number
    case .boolean:
      return .boolean
    case .array(_, let arrayContext):
      guard let items = arrayContext.items else {
        throw UnsupportedSpecConstruct(location: location, reason: "array schema without 'items'")
      }
      return .array(try parseType(items, location: location + "[]"))
    case .object(_, let objectContext) where objectContext.properties.isEmpty:
      return .freeform
    case .reference(let reference, _):
      guard let name = reference.name else {
        throw UnsupportedSpecConstruct(
          location: location, reason: "external reference without a resolvable name")
      }
      return .schemaRef(name)
    default:
      throw UnsupportedSpecConstruct(location: location, reason: "unsupported schema shape")
    }
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path tools/openapi-codegen --filter SchemaParsingTests`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add tools/openapi-codegen
git commit -m "feat(codegen): parse object and string-enum schemas into IR"
```

---

### Task 4: Type parsing extras — arrays, schema refs, freeform, fail-fast

**Files:**
- Modify: `tools/openapi-codegen/Sources/OpenAPICodegenCore/OpenAPIParsing.swift` (no code change needed — `parseType` from Task 3 already covers these; this task is tests-only, proving the behavior)
- Create: `tools/openapi-codegen/Tests/OpenAPICodegenCoreTests/TypeParsingTests.swift`

**Interfaces:**
- Consumes: `OpenAPIParsing.parseType(_:location:)`, `IRType` (from Task 3).

- [ ] **Step 1: Write the failing tests**

```swift
//
//  TypeParsingTests.swift
//

import OpenAPIKit30
import Testing

@testable import OpenAPICodegenCore

@Suite
struct TypeParsingTests {

  private func schema(_ json: String) throws -> JSONSchema {
    try JSONDecoder().decode(JSONSchema.self, from: Data(json.utf8))
  }

  @Test
  func parsesArrayOfStrings() throws {
    let type = try OpenAPIParsing.parseType(
      schema(#"{"type": "array", "items": {"type": "string"}}"#), location: "test")
    #expect(type == .array(.string))
  }

  @Test
  func rejectsArrayWithoutItems() throws {
    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseType(try schema(#"{"type": "array"}"#), location: "test")
    }
  }

  @Test
  func parsesSchemaReference() throws {
    let type = try OpenAPIParsing.parseType(
      schema(#"{"$ref": "#/components/schemas/bucketSchema"}"#), location: "test")
    #expect(type == .schemaRef("bucketSchema"))
  }

  @Test
  func parsesFreeformObject() throws {
    let type = try OpenAPIParsing.parseType(schema(#"{"type": "object"}"#), location: "test")
    #expect(type == .freeform)
  }

  @Test
  func rejectsInlineObjectWithProperties() throws {
    let json = #"{"type": "object", "properties": {"a": {"type": "string"}}}"#
    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseType(try schema(json), location: "test")
    }
  }

  @Test
  func rejectsOneOfUnion() throws {
    let json = """
      {"oneOf": [{"type": "string"}, {"type": "integer"}]}
      """
    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseType(try schema(json), location: "test")
    }
  }

  @Test
  func rejectsInlineEnum() throws {
    let json = #"{"type": "string", "enum": ["a", "b"]}"#
    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseType(try schema(json), location: "test")
    }
  }
}
```

- [ ] **Step 2: Run to verify current behavior**

Run: `swift test --package-path tools/openapi-codegen --filter TypeParsingTests`
Expected: PASS (7 tests) — `parseType` from Task 3 already handles all of these; this task exists to lock the behavior down with tests before the emitter starts depending on it.

- [ ] **Step 3: Commit**

```bash
git add tools/openapi-codegen
git commit -m "test(codegen): cover array/ref/freeform/fail-fast type parsing"
```

---

### Task 5: Parameter parsing

**Files:**
- Modify: `tools/openapi-codegen/Sources/OpenAPICodegenCore/OpenAPIParsing.swift`
- Create: `tools/openapi-codegen/Tests/OpenAPICodegenCoreTests/ParameterParsingTests.swift`

**Interfaces:**
- Produces: `OpenAPIParsing.parseParameter(_:location:)` — `(Either<JSONReference<OpenAPI.Parameter>, OpenAPI.Parameter>, location: String) throws -> IRParameter`. Used by Task 7's operation parsing.

- [ ] **Step 1: Write the failing test**

```swift
//
//  ParameterParsingTests.swift
//

import OpenAPIKit30
import Testing

@testable import OpenAPICodegenCore

@Suite
struct ParameterParsingTests {

  private func parameter(_ json: String) throws -> Either<
    JSONReference<OpenAPI.Parameter>, OpenAPI.Parameter
  > {
    let param = try JSONDecoder().decode(OpenAPI.Parameter.self, from: Data(json.utf8))
    return .b(param)
  }

  @Test
  func parsesRequiredPathParameter() throws {
    let json = """
      {"name": "bucketId", "in": "path", "required": true, "schema": {"type": "string"}}
      """
    let irParameter = try OpenAPIParsing.parseParameter(parameter(json), location: "op")

    #expect(irParameter.name == "bucketId")
    #expect(irParameter.location == .path)
    #expect(irParameter.type == .string)
    #expect(irParameter.isOptional == false)
  }

  @Test
  func parsesOptionalQueryParameter() throws {
    let json = """
      {"name": "limit", "in": "query", "schema": {"type": "integer"}}
      """
    let irParameter = try OpenAPIParsing.parseParameter(parameter(json), location: "op")

    #expect(irParameter.location == .query)
    #expect(irParameter.type == .integer)
    #expect(irParameter.isOptional == true)
  }

  @Test
  func parsesHeaderParameter() throws {
    let json = """
      {"name": "if-none-match", "in": "header", "schema": {"type": "string"}}
      """
    let irParameter = try OpenAPIParsing.parseParameter(parameter(json), location: "op")

    #expect(irParameter.location == .header)
  }

  @Test
  func rejectsCookieParameter() throws {
    let json = """
      {"name": "session", "in": "cookie", "schema": {"type": "string"}}
      """
    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseParameter(try parameter(json), location: "op")
    }
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path tools/openapi-codegen --filter ParameterParsingTests`
Expected: FAIL to compile (`parseParameter` not defined)

- [ ] **Step 3: Add `parseParameter` to `OpenAPIParsing.swift`**

Append inside the `OpenAPIParsing` enum, after the schema-parsing section:

```swift
  // MARK: - Parameters

  static func parseParameter(
    _ either: Either<JSONReference<OpenAPI.Parameter>, OpenAPI.Parameter>,
    location: String
  ) throws -> IRParameter {
    guard let parameter = either.parameterValue else {
      throw UnsupportedSpecConstruct(location: location, reason: "external parameter reference")
    }
    let parameterLocation = "\(location).\(parameter.name)"
    let irLocation: IRParameterLocation
    switch parameter.location {
    case .path: irLocation = .path
    case .query: irLocation = .query
    case .header: irLocation = .header
    case .cookie:
      throw UnsupportedSpecConstruct(
        location: parameterLocation, reason: "cookie parameters aren't supported")
    }
    guard let schema = parameter.schemaOrContent.schemaValue else {
      throw UnsupportedSpecConstruct(
        location: parameterLocation, reason: "parameter uses 'content' instead of 'schema'")
    }
    return IRParameter(
      name: parameter.name,
      location: irLocation,
      type: try parseType(schema, location: parameterLocation),
      isOptional: !parameter.required || schema.nullable
    )
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path tools/openapi-codegen --filter ParameterParsingTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add tools/openapi-codegen
git commit -m "feat(codegen): parse path/query/header parameters into IR"
```

---

### Task 6: Request body parsing (JSON + multipart)

**Files:**
- Modify: `tools/openapi-codegen/Sources/OpenAPICodegenCore/OpenAPIParsing.swift`
- Create: `tools/openapi-codegen/Tests/OpenAPICodegenCoreTests/RequestBodyParsingTests.swift`

**Interfaces:**
- Produces: `OpenAPIParsing.parseRequestBody(_:location:)` — `(Either<JSONReference<OpenAPI.Request>, OpenAPI.Request>, location: String) throws -> IRRequestBody`. Used by Task 7.
- Produces: `OpenAPIParsing.resolveSchema(_:location:)` — `(Either<JSONReference<JSONSchema>, JSONSchema>, location: String) throws -> IRType`. Used by Task 6 and Task 7.

- [ ] **Step 1: Write the failing test**

```swift
//
//  RequestBodyParsingTests.swift
//

import OpenAPIKit30
import Testing

@testable import OpenAPICodegenCore

@Suite
struct RequestBodyParsingTests {

  private func requestBody(_ json: String) throws -> Either<
    JSONReference<OpenAPI.Request>, OpenAPI.Request
  > {
    let request = try JSONDecoder().decode(OpenAPI.Request.self, from: Data(json.utf8))
    return .b(request)
  }

  @Test
  func parsesJSONRequestBody() throws {
    let json = """
      {
        "content": {
          "application/json": {"schema": {"$ref": "#/components/schemas/bucketUpdate"}}
        }
      }
      """
    let body = try OpenAPIParsing.parseRequestBody(requestBody(json), location: "updateBucket")

    #expect(body == .json(.schemaRef("bucketUpdate")))
  }

  @Test
  func parsesMultipartRequestBodyWithFileField() throws {
    let json = """
      {
        "content": {
          "multipart/form-data": {
            "schema": {
              "type": "object",
              "properties": {
                "cacheControl": {"type": "string"},
                "": {"type": "string", "format": "binary"}
              }
            }
          }
        }
      }
      """
    let body = try OpenAPIParsing.parseRequestBody(requestBody(json), location: "createObject")

    guard case .multipart(let fields) = body else {
      Issue.record("expected a multipart request body")
      return
    }
    let byName = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0) })
    #expect(byName["cacheControl"]?.isFile == false)
    #expect(byName[""]?.isFile == true)
  }

  @Test
  func rejectsUnsupportedContentType() throws {
    let json = """
      {"content": {"text/plain": {"schema": {"type": "string"}}}}
      """
    #expect(throws: UnsupportedSpecConstruct.self) {
      try OpenAPIParsing.parseRequestBody(try requestBody(json), location: "op")
    }
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path tools/openapi-codegen --filter RequestBodyParsingTests`
Expected: FAIL to compile (`parseRequestBody` not defined)

- [ ] **Step 3: Add `resolveSchema` and `parseRequestBody` to `OpenAPIParsing.swift`**

Append inside the `OpenAPIParsing` enum:

```swift
  // MARK: - Schema references in content bodies

  static func resolveSchema(
    _ either: Either<JSONReference<JSONSchema>, JSONSchema>,
    location: String
  ) throws -> IRType {
    switch either {
    case .a(let reference):
      guard let name = reference.name else {
        throw UnsupportedSpecConstruct(
          location: location, reason: "external schema reference without a resolvable name")
      }
      return .schemaRef(name)
    case .b(let schema):
      return try parseType(schema, location: location)
    }
  }

  // MARK: - Request bodies

  static func parseRequestBody(
    _ either: Either<JSONReference<OpenAPI.Request>, OpenAPI.Request>,
    location: String
  ) throws -> IRRequestBody {
    guard let request = either.requestValue else {
      throw UnsupportedSpecConstruct(location: location, reason: "external request body reference")
    }
    if let jsonContent = request.content.first(where: { $0.key.typeAndSubtype == "application/json" })?.value {
      guard let schema = jsonContent.schema else {
        throw UnsupportedSpecConstruct(location: location, reason: "JSON request body without a schema")
      }
      return .json(try resolveSchema(schema, location: location))
    }
    if let multipartContent = request.content.first(where: {
      $0.key.typeAndSubtype == "multipart/form-data"
    })?.value {
      guard let schemaEither = multipartContent.schema, case .b(let objectSchema) = schemaEither,
        case .object(_, let objectContext) = objectSchema.value
      else {
        throw UnsupportedSpecConstruct(
          location: location, reason: "multipart request body must be an inline object schema")
      }
      var fields: [IRMultipartField] = []
      for (fieldName, fieldSchema) in objectContext.properties {
        var isFile = false
        if case .string(let core, _) = fieldSchema.value, core.format == .binary {
          isFile = true
        }
        fields.append(
          IRMultipartField(
            name: fieldName,
            type: try parseType(fieldSchema, location: "\(location).\(fieldName)"),
            isFile: isFile
          )
        )
      }
      return .multipart(fields: fields)
    }
    let contentTypes = request.content.keys.map(\.rawValue).joined(separator: ", ")
    throw UnsupportedSpecConstruct(
      location: location, reason: "unsupported request body content type(s): \(contentTypes)")
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path tools/openapi-codegen --filter RequestBodyParsingTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add tools/openapi-codegen
git commit -m "feat(codegen): parse JSON and multipart request bodies into IR"
```

---

### Task 7: Response parsing + full document parsing

**Files:**
- Modify: `tools/openapi-codegen/Sources/OpenAPICodegenCore/OpenAPIParsing.swift`
- Create: `tools/openapi-codegen/Tests/OpenAPICodegenCoreTests/ResponseParsingTests.swift`

**Interfaces:**
- Produces: `OpenAPIParsing.parseResponses(_:location:)`, `OpenAPIParsing.parseOperations(_:)`, `OpenAPIParsing.parseDocument(_:)` — `(OpenAPI.Document) throws -> IRDocument`. `parseDocument` is the tool's single public entry point, used by Task 11's CLI.

- [ ] **Step 1: Write the failing test**

```swift
//
//  ResponseParsingTests.swift
//

import OpenAPIKit30
import Testing

@testable import OpenAPICodegenCore

@Suite
struct ResponseParsingTests {

  @Test
  func parsesSuccessAndErrorResponses() throws {
    let json = """
      {
        "200": {
          "description": "ok",
          "content": {"application/json": {"schema": {"$ref": "#/components/schemas/bucketSchema"}}}
        },
        "404": {
          "description": "not found",
          "content": {"application/json": {"schema": {"$ref": "#/components/schemas/errorSchema"}}}
        }
      }
      """
    let responses = try JSONDecoder().decode(OpenAPI.Response.Map.self, from: Data(json.utf8))

    let irResponses = try OpenAPIParsing.parseResponses(responses, location: "getBucket")

    #expect(irResponses.count == 2)
    #expect(irResponses[0].statusCode == 200)
    #expect(irResponses[0].isError == false)
    #expect(irResponses[0].body == .json(.schemaRef("bucketSchema")))
    #expect(irResponses[1].statusCode == 404)
    #expect(irResponses[1].isError == true)
    #expect(irResponses[1].body == .json(.schemaRef("errorSchema")))
  }

  @Test
  func parsesBinaryResponseBody() throws {
    let json = """
      {
        "200": {
          "description": "ok",
          "content": {"application/octet-stream": {"schema": {"type": "string", "format": "binary"}}}
        }
      }
      """
    let responses = try JSONDecoder().decode(OpenAPI.Response.Map.self, from: Data(json.utf8))

    let irResponses = try OpenAPIParsing.parseResponses(responses, location: "download")

    #expect(irResponses[0].body == .binary)
  }

  @Test
  func skipsDefaultAndRangeStatusEntries() throws {
    let json = """
      {
        "200": {"description": "ok", "content": {}},
        "default": {"description": "generic error", "content": {}}
      }
      """
    let responses = try JSONDecoder().decode(OpenAPI.Response.Map.self, from: Data(json.utf8))

    let irResponses = try OpenAPIParsing.parseResponses(responses, location: "op")

    #expect(irResponses.count == 1)
    #expect(irResponses[0].statusCode == 200)
  }

  @Test
  func parsesFullDocumentEndToEnd() throws {
    let json = """
      {
        "openapi": "3.0.3",
        "info": {"title": "Storage", "version": "1.0.0"},
        "paths": {
          "/bucket/{bucketId}": {
            "get": {
              "operationId": "getBucket",
              "parameters": [
                {"name": "bucketId", "in": "path", "required": true, "schema": {"type": "string"}}
              ],
              "responses": {
                "200": {
                  "description": "ok",
                  "content": {
                    "application/json": {"schema": {"$ref": "#/components/schemas/bucketSchema"}}
                  }
                }
              }
            }
          }
        },
        "components": {
          "schemas": {
            "bucketSchema": {
              "type": "object",
              "required": ["id"],
              "properties": {"id": {"type": "string"}}
            }
          }
        }
      }
      """
    let document = try JSONDecoder().decode(OpenAPI.Document.self, from: Data(json.utf8))

    let irDocument = try OpenAPIParsing.parseDocument(document)

    #expect(irDocument.schemas.map(\.name) == ["bucketSchema"])
    #expect(irDocument.operations.count == 1)
    #expect(irDocument.operations[0].operationId == "getBucket")
    #expect(irDocument.operations[0].method == .get)
    #expect(irDocument.operations[0].path == "/bucket/{bucketId}")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path tools/openapi-codegen --filter ResponseParsingTests`
Expected: FAIL to compile (`parseResponses`/`parseDocument` not defined)

- [ ] **Step 3: Add response and document parsing to `OpenAPIParsing.swift`**

Append inside the `OpenAPIParsing` enum:

```swift
  // MARK: - Responses

  static func parseResponses(
    _ responses: OpenAPI.Response.Map,
    location: String
  ) throws -> [IRResponse] {
    var results: [IRResponse] = []
    for (statusCode, responseEither) in responses {
      guard case .status(let code) = statusCode.value else {
        // `default` and range ("4XX") responses aren't modeled in v1; skip them.
        continue
      }
      guard let response = responseEither.responseValue else {
        throw UnsupportedSpecConstruct(
          location: location, reason: "external response reference for status \(code)")
      }
      let body = try parseResponseBody(response.content, location: "\(location) -> \(code)")
      results.append(IRResponse(statusCode: code, isError: !statusCode.isSuccess, body: body))
    }
    return results.sorted { $0.statusCode < $1.statusCode }
  }

  static func parseResponseBody(
    _ content: OpenAPI.Content.Map,
    location: String
  ) throws -> IRResponseBody {
    if let jsonContent = content.first(where: { $0.key.typeAndSubtype == "application/json" })?.value {
      guard let schema = jsonContent.schema else { return .none }
      return .json(try resolveSchema(schema, location: location))
    }
    return content.isEmpty ? .none : .binary
  }

  // MARK: - Operations

  static func parseOperations(_ document: OpenAPI.Document) throws -> [IROperation] {
    var operations: [IROperation] = []
    for (path, pathItemEither) in document.paths {
      guard let pathItem = pathItemEither.pathItemValue else {
        throw UnsupportedSpecConstruct(location: path.rawValue, reason: "external path item reference")
      }
      let methodOperations: [(IRHTTPMethod, OpenAPI.Operation?)] = [
        (.get, pathItem.get),
        (.put, pathItem.put),
        (.post, pathItem.post),
        (.delete, pathItem.delete),
        (.options, pathItem.options),
        (.head, pathItem.head),
        (.patch, pathItem.patch),
        (.trace, pathItem.trace),
      ]
      for (method, maybeOperation) in methodOperations {
        guard let operation = maybeOperation else { continue }
        let operationLocation = "\(method.rawValue.uppercased()) \(path.rawValue)"
        guard let operationId = operation.operationId else {
          throw UnsupportedSpecConstruct(location: operationLocation, reason: "missing operationId")
        }
        var parameters: [IRParameter] = []
        for parameterEither in pathItem.parameters + operation.parameters {
          parameters.append(try parseParameter(parameterEither, location: operationId))
        }
        let requestBody = try operation.requestBody.map {
          try parseRequestBody($0, location: operationId)
        }
        let responses = try parseResponses(operation.responses, location: operationId)
        operations.append(
          IROperation(
            operationId: operationId,
            method: method,
            path: path.rawValue,
            parameters: parameters,
            requestBody: requestBody,
            responses: responses
          )
        )
      }
    }
    return operations.sorted { $0.operationId < $1.operationId }
  }

  // MARK: - Document

  static func parseDocument(_ document: OpenAPI.Document) throws -> IRDocument {
    var schemas: [IRSchema] = []
    for (key, schema) in document.components.schemas {
      schemas.append(try parseNamedSchema(name: key.rawValue, schema: schema))
    }
    return IRDocument(
      schemas: schemas.sorted { $0.name < $1.name },
      operations: try parseOperations(document)
    )
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path tools/openapi-codegen --filter ResponseParsingTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Run the whole parsing test suite together**

Run: `swift test --package-path tools/openapi-codegen`
Expected: PASS (all tests from Tasks 3-7)

- [ ] **Step 6: Commit**

```bash
git add tools/openapi-codegen
git commit -m "feat(codegen): parse responses and wire up full-document parsing"
```

---

### Task 8: SwiftNames — identifier casing and escaping

**Files:**
- Create: `tools/openapi-codegen/Sources/OpenAPICodegenCore/SwiftNames.swift`
- Create: `tools/openapi-codegen/Tests/OpenAPICodegenCoreTests/SwiftNamesTests.swift`

**Interfaces:**
- Consumes: `IRType` (from Task 3).
- Produces: `SwiftNames.typeName(_:)`, `.propertyName(_:)`, `.typeReference(_:isOptional:)` — used by Tasks 9 and 10.

- [ ] **Step 1: Write the failing test**

```swift
//
//  SwiftNamesTests.swift
//

import Testing

@testable import OpenAPICodegenCore

@Suite
struct SwiftNamesTests {

  @Test
  func convertsSnakeCaseToLowerCamelCase() {
    #expect(SwiftNames.propertyName("file_size_limit") == "fileSizeLimit")
    #expect(SwiftNames.propertyName("id") == "id")
  }

  @Test
  func escapesReservedWords() {
    #expect(SwiftNames.propertyName("public") == "`public`")
    #expect(SwiftNames.propertyName("self") == "`self`")
  }

  @Test
  func convertsSchemaNameToUpperCamelCaseTypeName() {
    #expect(SwiftNames.typeName("bucketSchema") == "BucketSchema")
    #expect(SwiftNames.typeName("errorSchema") == "ErrorSchema")
  }

  @Test
  func rendersTypeReferences() {
    #expect(SwiftNames.typeReference(.string, isOptional: false) == "String")
    #expect(SwiftNames.typeReference(.integer, isOptional: true) == "Int?")
    #expect(SwiftNames.typeReference(.array(.string), isOptional: false) == "[String]")
    #expect(SwiftNames.typeReference(.schemaRef("bucketSchema"), isOptional: false) == "BucketSchema")
    #expect(SwiftNames.typeReference(.freeform, isOptional: false) == "[String: JSONValue]")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path tools/openapi-codegen --filter SwiftNamesTests`
Expected: FAIL to compile (`SwiftNames` not defined)

- [ ] **Step 3: Write `SwiftNames.swift`**

```swift
//
//  SwiftNames.swift
//

enum SwiftNames {

  static let reservedWords: Set<String> = [
    "public", "private", "internal", "fileprivate", "open",
    "self", "Self", "class", "struct", "enum", "protocol",
    "default", "for", "in", "if", "else", "switch", "case",
    "return", "func", "var", "let", "import", "extension", "static",
    "true", "false", "nil", "is", "as", "guard", "where", "continue", "break",
    "operator", "typealias", "associatedtype", "subscript", "init", "deinit",
  ]

  static func typeName(_ raw: String) -> String {
    let camel = camelCased(raw)
    guard let first = camel.first else { return camel }
    return first.uppercased() + camel.dropFirst()
  }

  static func propertyName(_ raw: String) -> String {
    escape(camelCased(raw))
  }

  private static func camelCased(_ raw: String) -> String {
    let parts = raw.split(whereSeparator: { $0 == "_" || $0 == "-" })
    guard let first = parts.first else { return raw }
    let rest = parts.dropFirst().map { part -> String in
      guard let firstCharacter = part.first else { return String(part) }
      return firstCharacter.uppercased() + part.dropFirst()
    }
    return ([String(first)] + rest).joined()
  }

  private static func escape(_ identifier: String) -> String {
    reservedWords.contains(identifier) ? "`\(identifier)`" : identifier
  }

  static func typeReference(_ type: IRType, isOptional: Bool) -> String {
    let base = baseTypeReference(type)
    return isOptional ? "\(base)?" : base
  }

  static func baseTypeReference(_ type: IRType) -> String {
    switch type {
    case .string: return "String"
    case .integer: return "Int"
    case .number: return "Double"
    case .boolean: return "Bool"
    case .array(let element): return "[\(baseTypeReference(element))]"
    case .schemaRef(let name): return typeName(name)
    case .freeform: return "[String: JSONValue]"
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path tools/openapi-codegen --filter SwiftNamesTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add tools/openapi-codegen
git commit -m "feat(codegen): add Swift identifier casing/escaping helpers"
```

---

### Task 9: Swift emitter — models

**Files:**
- Create: `tools/openapi-codegen/Sources/OpenAPICodegenCore/SwiftEmitter.swift`
- Create: `tools/openapi-codegen/Tests/OpenAPICodegenCoreTests/ModelEmitterTests.swift`

**Interfaces:**
- Consumes: `IRDocument`, `IRSchema`, `SwiftNames` (from Tasks 3, 8).
- Produces: `SwiftEmitter.emitModels(_:)` — `(IRDocument) -> String`. Used by Task 11's CLI.

- [ ] **Step 1: Write the failing test**

```swift
//
//  ModelEmitterTests.swift
//

import Testing

@testable import OpenAPICodegenCore

@Suite
struct ModelEmitterTests {

  @Test
  func emitsStructWithCodingKeys() {
    let document = IRDocument(
      schemas: [
        IRSchema(
          name: "bucketSchema",
          kind: .object(properties: [
            IRProperty(name: "id", type: .string, isOptional: false),
            IRProperty(name: "file_size_limit", type: .integer, isOptional: true),
          ])
        )
      ],
      operations: []
    )

    let output = SwiftEmitter.emitModels(document)

    #expect(output.contains("public struct BucketSchema: Codable, Sendable, Hashable {"))
    #expect(output.contains("public var id: String"))
    #expect(output.contains("public var fileSizeLimit: Int?"))
    #expect(output.contains(#"case fileSizeLimit = "file_size_limit""#))
  }

  @Test
  func emitsStringEnum() {
    let document = IRDocument(
      schemas: [IRSchema(name: "visibility", kind: .stringEnum(cases: ["public", "private"]))],
      operations: []
    )

    let output = SwiftEmitter.emitModels(document)

    #expect(output.contains("public enum Visibility: String, Codable, Sendable, Hashable {"))
    #expect(output.contains(#"case `public` = "public""#))
    #expect(output.contains(#"case `private` = "private""#))
  }

  @Test
  func marksSchemasReferencedByErrorResponsesAsAPIError() {
    let document = IRDocument(
      schemas: [
        IRSchema(
          name: "errorSchema",
          kind: .object(properties: [IRProperty(name: "message", type: .string, isOptional: false)])
        )
      ],
      operations: [
        IROperation(
          operationId: "getBucket",
          method: .get,
          path: "/bucket/{id}",
          parameters: [],
          requestBody: nil,
          responses: [
            IRResponse(statusCode: 404, isError: true, body: .json(.schemaRef("errorSchema")))
          ]
        )
      ]
    )

    let output = SwiftEmitter.emitModels(document)

    #expect(output.contains("public struct ErrorSchema: Codable, Sendable, Hashable, APIError {"))
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path tools/openapi-codegen --filter ModelEmitterTests`
Expected: FAIL to compile (`SwiftEmitter` not defined)

- [ ] **Step 3: Write `SwiftEmitter.swift` (models section)**

```swift
//
//  SwiftEmitter.swift
//

enum SwiftEmitter {

  static func emitModels(_ document: IRDocument) -> String {
    let errorSchemaNames = self.errorSchemaNames(in: document)
    var lines: [String] = [
      "// Code generated by openapi-codegen. DO NOT EDIT.",
      "",
      "import Foundation",
      "import HTTPRuntime",
      "",
    ]
    for schema in document.schemas.sorted(by: { $0.name < $1.name }) {
      lines.append(emitSchema(schema, isError: errorSchemaNames.contains(schema.name)))
      lines.append("")
    }
    return lines.joined(separator: "\n")
  }

  static func errorSchemaNames(in document: IRDocument) -> Set<String> {
    var names: Set<String> = []
    for operation in document.operations {
      for response in operation.responses where response.isError {
        if case .json(.schemaRef(let name)) = response.body {
          names.insert(name)
        }
      }
    }
    return names
  }

  static func emitSchema(_ schema: IRSchema, isError: Bool) -> String {
    let typeName = SwiftNames.typeName(schema.name)
    switch schema.kind {
    case .object(let properties):
      return emitStruct(named: typeName, properties: properties, isError: isError)
    case .stringEnum(let cases):
      return emitStringEnum(named: typeName, cases: cases, isError: isError)
    }
  }

  static func emitStruct(named typeName: String, properties: [IRProperty], isError: Bool) -> String {
    let conformances = (["Codable", "Sendable", "Hashable"] + (isError ? ["APIError"] : []))
      .joined(separator: ", ")
    var lines = ["public struct \(typeName): \(conformances) {"]
    for property in properties {
      let name = SwiftNames.propertyName(property.name)
      let type = SwiftNames.typeReference(property.type, isOptional: property.isOptional)
      lines.append("  public var \(name): \(type)")
    }
    lines.append("")
    lines.append("  enum CodingKeys: String, CodingKey {")
    for property in properties {
      let name = SwiftNames.propertyName(property.name)
      lines.append("    case \(name) = \"\(property.name)\"")
    }
    lines.append("  }")
    lines.append("}")
    return lines.joined(separator: "\n")
  }

  static func emitStringEnum(named typeName: String, cases: [String], isError: Bool) -> String {
    let conformances = (["String", "Codable", "Sendable", "Hashable"] + (isError ? ["APIError"] : []))
      .joined(separator: ", ")
    var lines = ["public enum \(typeName): \(conformances) {"]
    for value in cases {
      lines.append("  case \(SwiftNames.propertyName(value)) = \"\(value)\"")
    }
    lines.append("}")
    return lines.joined(separator: "\n")
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path tools/openapi-codegen --filter ModelEmitterTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add tools/openapi-codegen
git commit -m "feat(codegen): emit Swift models from IR schemas"
```

---

### Task 10: Swift emitter — client

**Files:**
- Modify: `tools/openapi-codegen/Sources/OpenAPICodegenCore/SwiftEmitter.swift`
- Create: `tools/openapi-codegen/Tests/OpenAPICodegenCoreTests/ClientEmitterTests.swift`

**Interfaces:**
- Produces: `SwiftEmitter.emitClient(_:clientName:)` — `(IRDocument, clientName: String) -> String`. Used by Task 11's CLI.

- [ ] **Step 1: Write the failing test**

```swift
//
//  ClientEmitterTests.swift
//

import Testing

@testable import OpenAPICodegenCore

@Suite
struct ClientEmitterTests {

  @Test
  func emitsJSONRoundTripOperation() {
    let document = IRDocument(
      schemas: [],
      operations: [
        IROperation(
          operationId: "getBucket",
          method: .get,
          path: "/bucket/{bucketId}",
          parameters: [
            IRParameter(name: "bucketId", location: .path, type: .string, isOptional: false)
          ],
          requestBody: nil,
          responses: [
            IRResponse(statusCode: 200, isError: false, body: .json(.schemaRef("bucketSchema"))),
            IRResponse(statusCode: 404, isError: true, body: .json(.schemaRef("errorSchema"))),
          ]
        )
      ]
    )

    let output = SwiftEmitter.emitClient(document, clientName: "StorageOpenAPIClient")

    #expect(output.contains("public struct StorageOpenAPIClient: Sendable {"))
    #expect(output.contains("public func getBucket(bucketId: String) async throws -> BucketSchema {"))
    #expect(
      output.contains(
        "HTTPRequestBuilder(method: .get, baseURL: baseURL, path: \"/bucket/\\(PathEncoding.segment(bucketId))\")"
      ))
    #expect(output.contains("try response.checkStatus(errorTypes: [404: ErrorSchema.self])"))
    #expect(output.contains("return try JSONCoding.decoder.decode(BucketSchema.self, from: response.body)"))
  }

  @Test
  func emitsMultipartUploadOperation() {
    let document = IRDocument(
      schemas: [],
      operations: [
        IROperation(
          operationId: "createObject",
          method: .post,
          path: "/object/{bucketId}",
          parameters: [
            IRParameter(name: "bucketId", location: .path, type: .string, isOptional: false)
          ],
          requestBody: .multipart(fields: [
            IRMultipartField(name: "file", type: .string, isFile: true),
            IRMultipartField(name: "cacheControl", type: .string, isFile: false),
          ]),
          responses: [
            IRResponse(statusCode: 200, isError: false, body: .none)
          ]
        )
      ]
    )

    let output = SwiftEmitter.emitClient(document, clientName: "StorageOpenAPIClient")

    #expect(output.contains("file: URL"))
    #expect(output.contains("cacheControl: String"))
    #expect(output.contains("source: .file(file)"))
    #expect(output.contains("builder.setBody(.multipart(formData))"))
  }

  @Test
  func emitsBinaryDownloadOperation() {
    let document = IRDocument(
      schemas: [],
      operations: [
        IROperation(
          operationId: "download",
          method: .get,
          path: "/object/{bucketId}",
          parameters: [
            IRParameter(name: "bucketId", location: .path, type: .string, isOptional: false)
          ],
          requestBody: nil,
          responses: [IRResponse(statusCode: 200, isError: false, body: .binary)]
        )
      ]
    )

    let output = SwiftEmitter.emitClient(document, clientName: "StorageOpenAPIClient")

    #expect(output.contains("-> AsyncThrowingStream<Data, any Error> {"))
    #expect(output.contains("transport.stream(try builder.build())"))
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path tools/openapi-codegen --filter ClientEmitterTests`
Expected: FAIL to compile (`emitClient` not defined)

- [ ] **Step 3: Append the client emitter to `SwiftEmitter.swift`**

```swift
  // MARK: - Client

  static func emitClient(_ document: IRDocument, clientName: String) -> String {
    let errorSchemaNames = self.errorSchemaNames(in: document)
    var lines: [String] = [
      "// Code generated by openapi-codegen. DO NOT EDIT.",
      "",
      "import Foundation",
      "import HTTPRuntime",
      "",
      "public struct \(clientName): Sendable {",
      "  private let baseURL: URL",
      "  private let transport: any HTTPTransport",
      "",
      "  public init(baseURL: URL, transport: any HTTPTransport = URLSessionTransport()) {",
      "    self.baseURL = baseURL",
      "    self.transport = transport",
      "  }",
    ]
    for operation in document.operations.sorted(by: { $0.operationId < $1.operationId }) {
      lines.append("")
      lines.append(contentsOf: emitOperation(operation, errorSchemaNames: errorSchemaNames))
    }
    lines.append("}")
    return lines.joined(separator: "\n")
  }

  static func emitOperation(_ operation: IROperation, errorSchemaNames: Set<String>) -> [String] {
    let methodName = SwiftNames.propertyName(operation.operationId)
    let parameters = operation.parameters.sorted { lhs, rhs in
      lhs.isOptional != rhs.isOptional ? !lhs.isOptional : lhs.name < rhs.name
    }
    var signatureParts = parameters.map { parameter -> String in
      let name = SwiftNames.propertyName(parameter.name)
      let type = SwiftNames.typeReference(parameter.type, isOptional: parameter.isOptional)
      return "\(name): \(type)\(parameter.isOptional ? " = nil" : "")"
    }
    if let requestBody = operation.requestBody {
      signatureParts.append(contentsOf: requestBodyParameters(requestBody))
    }
    let successResponse = operation.responses.first { !$0.isError }
    let returnType = returnTypeReference(for: successResponse)

    var lines: [String] = [
      "  public func \(methodName)(\(signatureParts.joined(separator: ", "))) async throws"
        + (returnType.map { " -> \($0)" } ?? "") + " {",
      "    var builder = HTTPRequestBuilder(method: .\(operation.method.rawValue), baseURL: baseURL, path: \"\(pathTemplate(operation))\")",
    ]
    for parameter in parameters where parameter.location == .query {
      lines.append("    builder.addQuery(\"\(parameter.name)\", \(stringConversionExpression(parameter)))")
    }
    for parameter in parameters where parameter.location == .header {
      lines.append("    builder.setHeader(\"\(parameter.name)\", \(stringConversionExpression(parameter)))")
    }
    if let requestBody = operation.requestBody {
      lines.append(contentsOf: requestBodyLines(requestBody))
    }
    if let successResponse, case .binary = successResponse.body {
      lines.append("    let stream = try await transport.stream(try builder.build())")
      lines.append("    guard stream.head.isSuccess else {")
      lines.append(
        "      throw HTTPError.unexpectedStatus(status: stream.head.status, body: Data())")
      lines.append("    }")
      lines.append("    return stream.body")
    } else {
      lines.append("    let response = try await transport.send(try builder.build())")
      lines.append(
        "    try response.checkStatus(errorTypes: \(errorTypesLiteral(operation, errorSchemaNames: errorSchemaNames)))"
      )
      if let successResponse, case .json(let type) = successResponse.body {
        let typeName = SwiftNames.typeReference(type, isOptional: false)
        lines.append("    return try JSONCoding.decoder.decode(\(typeName).self, from: response.body)")
      }
    }
    lines.append("  }")
    return lines
  }

  static func pathTemplate(_ operation: IROperation) -> String {
    var result = operation.path
    for parameter in operation.parameters where parameter.location == .path {
      let name = SwiftNames.propertyName(parameter.name)
      let stringExpr = parameter.type == .string ? name : "String(\(name))"
      result = result.replacingOccurrences(
        of: "{\(parameter.name)}", with: "\\(PathEncoding.segment(\(stringExpr)))")
    }
    return result
  }

  static func stringConversionExpression(_ parameter: IRParameter) -> String {
    let name = SwiftNames.propertyName(parameter.name)
    if case .string = parameter.type { return name }
    return parameter.isOptional ? "\(name).map(String.init)" : "String(\(name))"
  }

  static func requestBodyParameters(_ requestBody: IRRequestBody) -> [String] {
    switch requestBody {
    case .json(let type):
      return ["payload: \(SwiftNames.typeReference(type, isOptional: false))"]
    case .multipart(let fields):
      return fields.map { field in
        let name = SwiftNames.propertyName(field.name)
        let type = field.isFile ? "URL" : SwiftNames.typeReference(field.type, isOptional: false)
        return "\(name): \(type)"
      }
    }
  }

  static func requestBodyLines(_ requestBody: IRRequestBody) -> [String] {
    switch requestBody {
    case .json:
      return [
        "    builder.setHeader(\"Content-Type\", \"application/json\")",
        "    builder.setBody(.data(try JSONCoding.encoder.encode(payload)))",
      ]
    case .multipart(let fields):
      var lines = ["    var formData = MultipartFormData()"]
      for field in fields {
        let name = SwiftNames.propertyName(field.name)
        if field.isFile {
          lines.append(
            "    formData.append(MultipartFormData.Part(name: \"\(field.name)\", filename: \(name).lastPathComponent, contentType: \"application/octet-stream\", source: .file(\(name))))"
          )
        } else {
          lines.append(
            "    formData.append(MultipartFormData.Part(name: \"\(field.name)\", source: .data(Data(String(describing: \(name)).utf8))))"
          )
        }
      }
      lines.append("    builder.setHeader(\"Content-Type\", formData.contentType)")
      lines.append("    builder.setBody(.multipart(formData))")
      return lines
    }
  }

  static func returnTypeReference(for response: IRResponse?) -> String? {
    guard let response else { return nil }
    switch response.body {
    case .none: return nil
    case .json(let type): return SwiftNames.typeReference(type, isOptional: false)
    case .binary: return "AsyncThrowingStream<Data, any Error>"
    }
  }

  static func errorTypesLiteral(_ operation: IROperation, errorSchemaNames: Set<String>) -> String {
    var entries: [String] = []
    for response in operation.responses where response.isError {
      if case .json(.schemaRef(let name)) = response.body, errorSchemaNames.contains(name) {
        entries.append("\(response.statusCode): \(SwiftNames.typeName(name)).self")
      }
    }
    return "[\(entries.joined(separator: ", "))]"
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path tools/openapi-codegen --filter ClientEmitterTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Run the full test suite**

Run: `swift test --package-path tools/openapi-codegen`
Expected: PASS (all tests from Tasks 3-10)

- [ ] **Step 6: Commit**

```bash
git add tools/openapi-codegen
git commit -m "feat(codegen): emit a Swift HTTP client from IR operations"
```

---

### Task 11: CLI wiring + end-to-end fixture test

**Files:**
- Modify: `tools/openapi-codegen/Sources/openapi-codegen/main.swift`
- Create: `tools/openapi-codegen/Tests/openapi-codegenTests/EndToEndTests.swift`

**Interfaces:**
- Produces: the `openapi-codegen` CLI, invoked as `openapi-codegen --spec <path> --output <dir> --module <name>`. Used manually in Task 13.

- [ ] **Step 1: Write the failing end-to-end test**

This test exercises the full pipeline (`parseDocument` → `emitModels`/`emitClient`) the CLI wraps, without shelling out to the built binary.

```swift
//
//  EndToEndTests.swift
//

import Foundation
import OpenAPIKit30
import Testing

@testable import OpenAPICodegenCore

@Suite
struct EndToEndTests {

  @Test
  func generatesModelsAndClientFromAMinimalStorageLikeSpec() throws {
    let json = """
      {
        "openapi": "3.0.3",
        "info": {"title": "Storage", "version": "1.0.0"},
        "paths": {
          "/bucket/{bucketId}": {
            "get": {
              "operationId": "getBucket",
              "parameters": [
                {"name": "bucketId", "in": "path", "required": true, "schema": {"type": "string"}}
              ],
              "responses": {
                "200": {
                  "description": "ok",
                  "content": {
                    "application/json": {"schema": {"$ref": "#/components/schemas/bucketSchema"}}
                  }
                },
                "404": {
                  "description": "not found",
                  "content": {
                    "application/json": {"schema": {"$ref": "#/components/schemas/errorSchema"}}
                  }
                }
              }
            }
          }
        },
        "components": {
          "schemas": {
            "bucketSchema": {
              "type": "object",
              "required": ["id", "public"],
              "properties": {
                "id": {"type": "string"},
                "public": {"type": "boolean"}
              }
            },
            "errorSchema": {
              "type": "object",
              "required": ["message"],
              "properties": {"message": {"type": "string"}}
            }
          }
        }
      }
      """
    let document = try JSONDecoder().decode(OpenAPI.Document.self, from: Data(json.utf8))
    let irDocument = try OpenAPIParsing.parseDocument(document)

    let models = SwiftEmitter.emitModels(irDocument)
    let client = SwiftEmitter.emitClient(irDocument, clientName: "StorageOpenAPIClient")

    #expect(models.contains("public struct BucketSchema: Codable, Sendable, Hashable {"))
    #expect(models.contains("public var `public`: Bool"))
    #expect(models.contains("public struct ErrorSchema: Codable, Sendable, Hashable, APIError {"))
    #expect(client.contains("public func getBucket(bucketId: String) async throws -> BucketSchema {"))
    #expect(client.contains("errorTypes: [404: ErrorSchema.self]"))
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path tools/openapi-codegen --filter EndToEndTests`
Expected: FAIL — `import OpenAPIKit30` in the executable's test target isn't declared yet.

Add `.product(name: "OpenAPIKit30", package: "OpenAPIKit")` to the `openapi-codegenTests` target's `dependencies` in `tools/openapi-codegen/Package.swift`, then re-run.
Expected: FAIL — assertions fail because `main.swift` doesn't exercise this path yet (this test targets `OpenAPICodegenCore` directly, so it should actually compile and pass once the dependency is added; if any assertion fails, fix the emitter/parser code from Tasks 3-10, not this test).

- [ ] **Step 3: Run again after adding the dependency**

Run: `swift test --package-path tools/openapi-codegen --filter EndToEndTests`
Expected: PASS

- [ ] **Step 4: Write the real CLI in `main.swift`**

```swift
//
//  main.swift
//

import Foundation
import OpenAPICodegenCore
import OpenAPIKit30

struct CLIError: Error, CustomStringConvertible {
  var description: String
}

func parseArguments(_ arguments: [String]) throws -> (spec: URL, output: URL, module: String) {
  var spec: String?
  var output: String?
  var module: String?
  var index = 0
  while index < arguments.count {
    switch arguments[index] {
    case "--spec":
      index += 1
      spec = arguments[index]
    case "--output":
      index += 1
      output = arguments[index]
    case "--module":
      index += 1
      module = arguments[index]
    default:
      throw CLIError(description: "unknown argument: \(arguments[index])")
    }
    index += 1
  }
  guard let spec, let output, let module else {
    throw CLIError(description: "usage: openapi-codegen --spec <path> --output <dir> --module <name>")
  }
  return (
    URL(fileURLWithPath: spec), URL(fileURLWithPath: output, isDirectory: true), module
  )
}

let (specURL, outputURL, moduleName) = try parseArguments(Array(CommandLine.arguments.dropFirst()))

let data = try Data(contentsOf: specURL)
let document = try JSONDecoder().decode(OpenAPI.Document.self, from: data)
let irDocument = try OpenAPIParsing.parseDocument(document)

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let models = SwiftEmitter.emitModels(irDocument)
try models.write(to: outputURL.appendingPathComponent("Models.swift"), atomically: true, encoding: .utf8)

let clientName = "\(moduleName)Client"
let client = SwiftEmitter.emitClient(irDocument, clientName: clientName)
try client.write(
  to: outputURL.appendingPathComponent("\(clientName).swift"), atomically: true, encoding: .utf8)

print("Generated \(irDocument.schemas.count) schemas and \(irDocument.operations.count) operations into \(outputURL.path)")
```

- [ ] **Step 5: Run the tool against the end-to-end fixture manually**

```bash
mkdir -p /tmp/openapi-codegen-smoke
cat > /tmp/openapi-codegen-smoke/spec.json <<'EOF'
{
  "openapi": "3.0.3",
  "info": {"title": "Smoke", "version": "1.0.0"},
  "paths": {
    "/bucket/{bucketId}": {
      "get": {
        "operationId": "getBucket",
        "parameters": [
          {"name": "bucketId", "in": "path", "required": true, "schema": {"type": "string"}}
        ],
        "responses": {
          "200": {
            "description": "ok",
            "content": {"application/json": {"schema": {"$ref": "#/components/schemas/bucketSchema"}}}
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "bucketSchema": {
        "type": "object",
        "required": ["id"],
        "properties": {"id": {"type": "string"}}
      }
    }
  }
}
EOF
swift run --package-path tools/openapi-codegen openapi-codegen \
  --spec /tmp/openapi-codegen-smoke/spec.json \
  --output /tmp/openapi-codegen-smoke/out \
  --module Smoke
cat /tmp/openapi-codegen-smoke/out/Models.swift
cat /tmp/openapi-codegen-smoke/out/SmokeClient.swift
```

Expected: prints `Generated 1 schemas and 1 operations into ...`, and both files contain the expected `BucketSchema` struct and `SmokeClient.getBucket` method.

- [ ] **Step 6: Commit**

```bash
git add tools/openapi-codegen
git commit -m "feat(codegen): wire up the openapi-codegen CLI"
```

---

### Task 12: Acquire and commit `openapi/storage.json`

**Files:**
- Create: `openapi/storage.json`

**Interfaces:**
- Produces: the input spec Task 13 generates from.

- [ ] **Step 1: Generate the spec from storage's PR branch**

Storage doesn't publish a static OpenAPI file — it's produced on demand by a script. Check out the branch from [storage#1215](https://github.com/supabase/storage/pull/1215) and export it:

```bash
git clone --depth 1 --branch claude/reverent-ramanujan-32755f https://github.com/supabase/storage.git /tmp/storage-spec-export
cd /tmp/storage-spec-export
npm ci
npm run docs:export
```

Expected: this produces `static/api.json` (confirm the exact output path by checking `src/scripts/export-docs.ts` if it differs) inside `/tmp/storage-spec-export`.

- [ ] **Step 2: Copy and validate the spec**

```bash
cp /tmp/storage-spec-export/static/api.json <repo>/openapi/storage.json
python3 -m json.tool <repo>/openapi/storage.json > /dev/null
```

Expected: no output from `json.tool` (valid JSON); replace `<repo>` with this repository's absolute path.

- [ ] **Step 3: Confirm the tool can parse it without error**

```bash
swift run --package-path tools/openapi-codegen openapi-codegen \
  --spec openapi/storage.json \
  --output /tmp/storage-openapi-dry-run \
  --module StorageOpenAPI
```

Expected: prints `Generated N schemas and M operations into /tmp/storage-openapi-dry-run` with no thrown `UnsupportedSpecConstruct`. If it throws, read the error's `location`/`reason`, decide whether the parser needs a small extension or the spec has a construct genuinely out of v1 scope, and note the decision in the commit message — don't silently loosen the fail-fast check without recording why.

- [ ] **Step 4: Commit the spec**

```bash
git add openapi/storage.json
git commit -m "docs(storage): commit the OpenAPI spec fixed by storage#1215"
```

---

### Task 13: Generate `Sources/StorageOpenAPI` and wire it into the main package

**Files:**
- Create: `Sources/StorageOpenAPI/Models.swift`
- Create: `Sources/StorageOpenAPI/StorageOpenAPIClient.swift`
- Modify: `Package.swift`

**Interfaces:**
- Produces: `StorageOpenAPI` target (public types + `StorageOpenAPIClient`), consumed by Task 14's tests.

- [ ] **Step 1: Generate the client**

```bash
swift run --package-path tools/openapi-codegen openapi-codegen \
  --spec openapi/storage.json \
  --output Sources/StorageOpenAPI \
  --module StorageOpenAPI
```

- [ ] **Step 2: Register the `StorageOpenAPI` target in `Package.swift`**

Add this block right after the `StorageTests` target (grouped with the rest of the Storage-related targets):

```swift
    .target(
      name: "StorageOpenAPI",
      dependencies: [
        "HTTPRuntime"
      ]
    ),
    .testTarget(
      name: "StorageOpenAPITests",
      dependencies: [
        "StorageOpenAPI",
        "HTTPRuntime",
      ]
    ),
```

Add `"StorageOpenAPITests"` to the `swift6TestTargets` set:

```swift
let swift6TestTargets: Set<String> = [
  "SupabaseTests", "HelpersTests", "HTTPRuntimeTests", "StorageOpenAPITests",
]
```

- [ ] **Step 3: Format the generated files and build**

```bash
./scripts/format.sh
swift build --target StorageOpenAPI
```

Expected: `Build complete!`. If it fails, the error will point at a specific emitted construct — fix the relevant `SwiftEmitter`/`OpenAPIParsing` function in `tools/openapi-codegen` (not by hand-editing the generated file, which gets overwritten next run), regenerate, and rebuild.

- [ ] **Step 4: Commit**

```bash
git add Sources/StorageOpenAPI Package.swift
git commit -m "feat(storage): generate the OpenAPI-based Storage client"
```

---

### Task 14: Tests proving the generated client works

**Files:**
- Create: `Tests/StorageOpenAPITests/BucketOperationsTests.swift`
- Create: `Tests/StorageOpenAPITests/ErrorDecodingTests.swift`

**Interfaces:**
- Consumes: `StorageOpenAPIClient`, generated model types from `Sources/StorageOpenAPI` (Task 13), `HTTPTransport`/`HTTPResponse`/`HTTPResponseHead` from `HTTPRuntime` (Task 1).

This task's exact operation/type names depend on what Task 13 actually generated from the real spec — read `Sources/StorageOpenAPI/StorageOpenAPIClient.swift` first to confirm the method name for "get a bucket" (expected: `getBucket(bucketId:)`, per `storage#1215`'s documented `operationId`s) and the 404 error type (expected: `ErrorSchema`) before writing these tests. Adjust names below if the real spec produced something different — do not change the generator to match a guess made before reading its actual output.

- [ ] **Step 1: Write a fake `HTTPTransport` shared by these tests**

```swift
//
//  BucketOperationsTests.swift
//

import Foundation
import HTTPRuntime
import Testing

@testable import StorageOpenAPI

private struct FakeTransport: HTTPTransport {
  var onSend: @Sendable (HTTPRequest) throws -> HTTPResponse

  func send(_ request: HTTPRequest, uploadProgress: ProgressHandler?) async throws -> HTTPResponse {
    try onSend(request)
  }

  func stream(_ request: HTTPRequest) async throws -> HTTPResponseStream {
    let response = try onSend(request)
    return HTTPResponseStream(
      head: response.head,
      body: AsyncThrowingStream { continuation in
        continuation.yield(response.body)
        continuation.finish()
      }
    )
  }
}

@Suite
struct BucketOperationsTests {

  @Test
  func getBucketDecodesASuccessResponse() async throws {
    let responseBody = Data(#"{"id":"avatars","public":true}"#.utf8)
    let transport = FakeTransport { request in
      #expect(request.url.path.hasSuffix("/bucket/avatars"))
      return HTTPResponse(head: HTTPResponseHead(status: 200, headers: [:]), body: responseBody)
    }
    let client = StorageOpenAPIClient(baseURL: URL(string: "https://example.supabase.co/storage/v1")!, transport: transport)

    let bucket = try await client.getBucket(bucketId: "avatars")

    #expect(bucket.id == "avatars")
    #expect(bucket.public == true)
  }
}
```

- [ ] **Step 2: Run to verify it fails or passes as expected**

Run: `swift test --filter StorageOpenAPITests`
Expected: PASS if `getBucket`/`BucketSchema.id`/`.public` match the real generated names exactly; if a name differs (e.g. the spec's actual property is `public` but got escaped differently, or the operationId differs), fix this test to match the generated code's real names — the generator mirrors the spec verbatim, so the spec is the source of truth here, not this test's guess.

- [ ] **Step 3: Write the multipart upload test**

```swift
//
//  ObjectUploadTests.swift
//

import Foundation
import HTTPRuntime
import Testing

@testable import StorageOpenAPI

@Suite
struct ObjectUploadTests {

  @Test
  func createObjectSendsAMultipartBody() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString).txt")
    try Data("hello".utf8).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let transport = FakeTransport { request in
      guard case .multipart(let formData) = request.body else {
        Issue.record("expected a multipart request body")
        return HTTPResponse(head: HTTPResponseHead(status: 500, headers: [:]), body: Data())
      }
      #expect(request.headers["Content-Type"] == formData.contentType)
      return HTTPResponse(head: HTTPResponseHead(status: 200, headers: [:]), body: Data())
    }
    let client = StorageOpenAPIClient(
      baseURL: URL(string: "https://example.supabase.co/storage/v1")!, transport: transport)

    // Read Sources/StorageOpenAPI/StorageOpenAPIClient.swift to confirm the exact
    // generated signature for the object-creation operation before finalizing this call.
    _ = try await client.createObject(bucketId: "avatars", wildcard: "a.txt", file: fileURL)
  }
}
```

- [ ] **Step 4: Run and reconcile against the real generated signature**

Run: `swift test --filter StorageOpenAPITests`
Expected: fix the call site to match whatever `Sources/StorageOpenAPI/StorageOpenAPIClient.swift` actually generated (parameter names/order come straight from the spec's path params + multipart fields).

- [ ] **Step 5: Write the typed-error decoding test**

```swift
//
//  ErrorDecodingTests.swift
//

import Foundation
import HTTPRuntime
import Testing

@testable import StorageOpenAPI

@Suite
struct ErrorDecodingTests {

  @Test
  func getBucketThrowsATypedErrorOn404() async throws {
    let errorBody = Data(#"{"message":"Bucket not found","error":"not_found","statusCode":"404"}"#.utf8)
    let transport = FakeTransport { _ in
      HTTPResponse(head: HTTPResponseHead(status: 404, headers: [:]), body: errorBody)
    }
    let client = StorageOpenAPIClient(
      baseURL: URL(string: "https://example.supabase.co/storage/v1")!, transport: transport)

    await #expect(throws: ErrorSchema.self) {
      _ = try await client.getBucket(bucketId: "missing")
    }
  }
}
```

- [ ] **Step 6: Run and reconcile against the real `errorSchema` shape**

Run: `swift test --filter StorageOpenAPITests`
Expected: fix `errorBody`'s JSON keys to match whatever properties the real `errorSchema` component declares (read `Sources/StorageOpenAPI/Models.swift`'s `ErrorSchema` struct) — then PASS.

- [ ] **Step 7: Format and commit**

```bash
./scripts/format.sh
git add Tests/StorageOpenAPITests
git commit -m "test(storage): cover the generated OpenAPI client's core paths"
```

---

### Task 15: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full main-package test suite the way this repo's contributors do**

```bash
PLATFORM=IOS XCODEBUILD_ARGUMENT=test ./scripts/xcodebuild.sh
```

Expected: all tests pass, including `HTTPRuntimeTests` and `StorageOpenAPITests`, with no regressions in existing modules (`Auth`, `Storage`, etc. — untouched by this plan).

- [ ] **Step 2: Run the standalone tool's test suite**

```bash
swift test --package-path tools/openapi-codegen
```

Expected: all tests pass.

- [ ] **Step 3: Confirm formatting is clean**

```bash
./scripts/format.sh
git status --porcelain
```

Expected: no output (nothing left unformatted/uncommitted from the main package). `tools/openapi-codegen` is a separate package not covered by this repo's `swift-format` config — skip it here.

- [ ] **Step 4: Spell-check the new files**

```bash
npm ci --prefix tools/node
./scripts/spell-check.sh
```

Expected: passes, or add any new legitimate technical terms (e.g. `openapi`, schema names) to `dictionary.txt`.

- [ ] **Step 5: Confirm nothing outside this plan's scope changed**

```bash
git diff --stat main...HEAD
```

Expected: only files under `openapi/`, `tools/openapi-codegen/`, `Sources/HTTPRuntime/`, `Sources/StorageOpenAPI/`, `Tests/HTTPRuntimeTests/`, `Tests/StorageOpenAPITests/`, `docs/superpowers/`, and `Package.swift`. `StorageFileApi.swift`/`StorageBucketApi.swift`/`Types.swift`/`SupabaseStorage.swift` must be untouched, per this plan's explicit scope boundary.
