# Storage Typed Value Types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backport typed value types and API ergonomics from the v3 branch into v2 without any breaking changes — all existing call sites compile unchanged.

**Architecture:** New value types (`StorageByteCount`, `ResizeMode`, `ImageFormat`, `SortOrder`, `DownloadBehavior`, `UploadMethod`, `StorageErrorCode`) are added to `Types.swift`, which also absorbs the content of `BucketOptions.swift` and `TransformOptions.swift`. Existing field types on `TransformOptions` and `SortBy` are evolved using `ExpressibleByStringLiteral` so string-literal call sites keep compiling. `BucketOptions` is cleaned up with deprecated bridge shims for backward compat. `StorageError` gains a computed `errorCode` property. `DownloadBehavior` overloads replace the deprecated `Bool` overloads.

**Tech Stack:** Swift 5.10+, XCTest (existing test files), Swift Testing (`import Testing`) for new test files, `make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild` to run tests.

## Global Constraints

- Zero breaking changes — every existing call site compiles unchanged
- New test files use Swift Testing (`import Testing`, `@Test`, `#expect`, `@Suite`)
- Existing test files keep their current framework (XCTest)
- 2-space indentation (project standard)
- Run `make format` after each task before committing
- Target: PR against `main`

---

### Task 1: New value types

**Files:**
- Modify: `Sources/Storage/Types.swift` (append new types at the end)
- Create: `Tests/StorageTests/ValueTypesTests.swift`

**Interfaces:**
- Produces:
  - `StorageByteCount` — `struct`, `bytes: Int64`, `.kilobytes(_:)`, `.megabytes(_:)`, `.gigabytes(_:)`, `ExpressibleByIntegerLiteral`
  - `ResizeMode` — `struct`, `.cover`, `.contain`, `.fill`, `ExpressibleByStringLiteral`, `Codable`
  - `ImageFormat` — `struct`, `.origin`, `.webp`, `.avif`, `ExpressibleByStringLiteral`, `Codable`
  - `SortOrder` — `struct`, `.ascending`, `.descending`, `ExpressibleByStringLiteral`, `Codable`
  - `DownloadBehavior` — `enum`, `.withOriginalName`, `.named(String)`, `var queryValue: String`
  - `UploadMethod` — `enum`, `.auto`, `.multipart`, `.resumable`

- [ ] **Step 1: Create the failing test file**

Create `Tests/StorageTests/ValueTypesTests.swift`:

```swift
import Testing
@testable import Storage

// MARK: - StorageByteCount

@Suite struct StorageByteCountTests {
  @Test func bytes() {
    #expect(StorageByteCount.bytes(1024).bytes == 1024)
  }

  @Test func kilobytes() {
    #expect(StorageByteCount.kilobytes(10).bytes == 10_240)
  }

  @Test func megabytes() {
    #expect(StorageByteCount.megabytes(5).bytes == 5_242_880)
  }

  @Test func gigabytes() {
    #expect(StorageByteCount.gigabytes(1).bytes == 1_073_741_824)
  }

  @Test func integerLiteral() {
    let count: StorageByteCount = 2048
    #expect(count.bytes == 2048)
  }

  @Test func equality() {
    #expect(StorageByteCount.megabytes(1) == StorageByteCount(1_048_576))
  }
}

// MARK: - ResizeMode

@Suite struct ResizeModeTests {
  @Test func staticConstants() {
    #expect(ResizeMode.cover.rawValue == "cover")
    #expect(ResizeMode.contain.rawValue == "contain")
    #expect(ResizeMode.fill.rawValue == "fill")
  }

  @Test func stringLiteral() {
    let mode: ResizeMode = "cover"
    #expect(mode == .cover)
  }

  @Test func customValue() {
    let mode = ResizeMode(rawValue: "custom")
    #expect(mode.rawValue == "custom")
  }

  @Test func encodes() throws {
    let encoded = try JSONEncoder().encode(ResizeMode.cover)
    #expect(String(data: encoded, encoding: .utf8) == "\"cover\"")
  }

  @Test func decodes() throws {
    let data = "\"contain\"".data(using: .utf8)!
    let mode = try JSONDecoder().decode(ResizeMode.self, from: data)
    #expect(mode == .contain)
  }
}

// MARK: - ImageFormat

@Suite struct ImageFormatTests {
  @Test func staticConstants() {
    #expect(ImageFormat.origin.rawValue == "origin")
    #expect(ImageFormat.webp.rawValue == "webp")
    #expect(ImageFormat.avif.rawValue == "avif")
  }

  @Test func stringLiteral() {
    let format: ImageFormat = "webp"
    #expect(format == .webp)
  }

  @Test func encodes() throws {
    let encoded = try JSONEncoder().encode(ImageFormat.webp)
    #expect(String(data: encoded, encoding: .utf8) == "\"webp\"")
  }

  @Test func decodes() throws {
    let data = "\"avif\"".data(using: .utf8)!
    let format = try JSONDecoder().decode(ImageFormat.self, from: data)
    #expect(format == .avif)
  }
}

// MARK: - SortOrder

@Suite struct SortOrderTests {
  @Test func staticConstants() {
    #expect(SortOrder.ascending.rawValue == "asc")
    #expect(SortOrder.descending.rawValue == "desc")
  }

  @Test func stringLiteral() {
    let order: SortOrder = "asc"
    #expect(order == .ascending)
  }

  @Test func encodes() throws {
    let encoded = try JSONEncoder().encode(SortOrder.descending)
    #expect(String(data: encoded, encoding: .utf8) == "\"desc\"")
  }
}

// MARK: - DownloadBehavior

@Suite struct DownloadBehaviorTests {
  @Test func withOriginalNameQueryValue() {
    #expect(DownloadBehavior.withOriginalName.queryValue == "")
  }

  @Test func namedQueryValue() {
    #expect(DownloadBehavior.named("report.pdf").queryValue == "report.pdf")
  }
}

// MARK: - UploadMethod

@Suite struct UploadMethodTests {
  @Test func casesExist() {
    let methods: [UploadMethod] = [.auto, .multipart, .resumable]
    #expect(methods.count == 3)
  }
}
```

- [ ] **Step 2: Run tests — expect compile failure (types don't exist yet)**

```bash
swift test --filter StorageTests 2>&1 | head -20
```

Expected: compile error mentioning `StorageByteCount`, `ResizeMode`, etc.

- [ ] **Step 3: Add new types to `Sources/Storage/Types.swift`**

Append after the last `}` in the file:

```swift
// MARK: - StorageByteCount

/// A strongly-typed file size value.
///
/// ```swift
/// BucketOptions(fileSizeLimit: .megabytes(5))
/// BucketOptions(fileSizeLimit: 10_485_760)  // raw bytes via integer literal
/// ```
public struct StorageByteCount: Sendable, Hashable {
  /// The raw byte count.
  public let bytes: Int64

  public init(_ bytes: Int64) { self.bytes = bytes }

  public static func bytes(_ value: Int64) -> Self { Self(value) }
  public static func kilobytes(_ value: Int64) -> Self { Self(value * 1_024) }
  public static func megabytes(_ value: Int64) -> Self { Self(value * 1_024 * 1_024) }
  public static func gigabytes(_ value: Int64) -> Self { Self(value * 1_024 * 1_024 * 1_024) }
}

extension StorageByteCount: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int64) { self.init(value) }
}

// MARK: - ResizeMode

/// Resize mode for on-the-fly image transformation.
///
/// Open-ended struct so custom backend values don't require an SDK update.
/// ```swift
/// TransformOptions(resize: .cover)
/// TransformOptions(resize: "cover")  // string literal still works
/// ```
public struct ResizeMode: RawRepresentable, Hashable, Sendable {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let cover = ResizeMode(rawValue: "cover")
  public static let contain = ResizeMode(rawValue: "contain")
  public static let fill = ResizeMode(rawValue: "fill")
}

extension ResizeMode: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension ResizeMode: Codable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }
}

// MARK: - ImageFormat

/// Output format for on-the-fly image transformation.
///
/// Open-ended struct so custom backend values don't require an SDK update.
/// ```swift
/// TransformOptions(format: .webp)
/// TransformOptions(format: "webp")  // string literal still works
/// ```
public struct ImageFormat: RawRepresentable, Hashable, Sendable {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let origin = ImageFormat(rawValue: "origin")
  public static let webp = ImageFormat(rawValue: "webp")
  public static let avif = ImageFormat(rawValue: "avif")
}

extension ImageFormat: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension ImageFormat: Codable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }
}

// MARK: - SortOrder

/// Sort direction for ``StorageFileApi/list(path:options:)`` results.
///
/// Open-ended struct so custom backend values don't require an SDK update.
/// ```swift
/// SortBy(column: "name", order: .ascending)
/// SortBy(column: "name", order: "asc")  // string literal still works
/// ```
public struct SortOrder: RawRepresentable, Hashable, Sendable {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let ascending = SortOrder(rawValue: "asc")
  public static let descending = SortOrder(rawValue: "desc")
}

extension SortOrder: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension SortOrder: Codable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }
}

// MARK: - DownloadBehavior

/// Controls the `?download=` query parameter on signed and public URLs.
///
/// ```swift
/// storage.from("docs").getPublicURL(path: "report.pdf", download: .withOriginalName)
/// storage.from("docs").getPublicURL(path: "report.pdf", download: .named("annual-2024.pdf"))
/// ```
public enum DownloadBehavior: Sendable {
  /// Trigger a browser download using the file's original name. Wire: `?download=`
  case withOriginalName
  /// Trigger a browser download with a custom filename. Wire: `?download=<name>`
  case named(String)

  var queryValue: String {
    switch self {
    case .withOriginalName: return ""
    case .named(let name): return name
    }
  }
}

// MARK: - UploadMethod

/// The upload protocol used when uploading files to Storage.
///
/// Pass to upload methods to override automatic protocol selection.
/// ```swift
/// storage.from("videos").upload("clip.mp4", fileURL: url, method: .resumable)
/// ```
public enum UploadMethod: Sendable {
  /// Choose automatically: files ≤ 6 MB use multipart, larger files use TUS resumable.
  case auto
  /// Force a single multipart HTTP request regardless of file size.
  case multipart
  /// Force TUS resumable uploads regardless of file size. Supports pause/resume/cancel.
  case resumable
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
swift test --filter StorageTests 2>&1 | tail -20
```

Expected: All `ValueTypesTests` pass.

- [ ] **Step 5: Format**

```bash
make format
```

- [ ] **Step 6: Commit**

```bash
git add Sources/Storage/Types.swift Tests/StorageTests/ValueTypesTests.swift
git commit -m "feat(storage): add StorageByteCount, ResizeMode, ImageFormat, SortOrder, DownloadBehavior, UploadMethod types"
```

---

### Task 2: StorageErrorCode + StorageError extension

**Files:**
- Modify: `Sources/Storage/StorageError.swift`
- Modify: `Tests/StorageTests/StorageErrorTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1
- Produces:
  - `StorageErrorCode` — `struct`, `rawValue: String`, static constants: `.unknown`, `.invalidJWT`, `.unauthorized`, `.objectNotFound`, `.bucketNotFound`, `.objectAlreadyExists`, `.bucketAlreadyExists`, `.invalidBucketName`, `.entityTooLarge`, `.invalidMimeType`
  - `StorageError.errorCode: StorageErrorCode` — computed, derived from `self.error`
  - `StorageError.isNotFound: Bool`
  - `StorageError.isUnauthorized: Bool`
  - `StorageError.isEntityTooLarge: Bool`

- [ ] **Step 1: Add failing tests to `Tests/StorageTests/StorageErrorTests.swift`**

Append inside the `StorageErrorTests` class, after the last existing test:

```swift
  func testErrorCode_objectNotFound() {
    let error = StorageError(statusCode: "404", message: "not found", error: "not_found")
    XCTAssertEqual(error.errorCode, .objectNotFound)
  }

  func testErrorCode_unauthorized() {
    let error = StorageError(statusCode: "401", message: "unauthorized", error: "Unauthorized")
    XCTAssertEqual(error.errorCode, .unauthorized)
  }

  func testErrorCode_entityTooLarge() {
    let error = StorageError(statusCode: "413", message: "too large", error: "Payload too large")
    XCTAssertEqual(error.errorCode, .entityTooLarge)
  }

  func testErrorCode_unknownFallback() {
    let error = StorageError(statusCode: nil, message: "oops", error: nil)
    XCTAssertEqual(error.errorCode, .unknown)
  }

  func testErrorCode_customString() {
    let error = StorageError(statusCode: "400", message: "bad", error: "some_new_server_code")
    XCTAssertEqual(error.errorCode.rawValue, "some_new_server_code")
  }

  func testIsNotFound_objectNotFound() {
    let error = StorageError(statusCode: "404", message: "not found", error: "not_found")
    XCTAssertTrue(error.isNotFound)
  }

  func testIsNotFound_bucketNotFound() {
    let error = StorageError(statusCode: "404", message: "bucket not found", error: "Bucket not found")
    XCTAssertTrue(error.isNotFound)
  }

  func testIsNotFound_falseForOtherErrors() {
    let error = StorageError(statusCode: "403", message: "unauthorized", error: "Unauthorized")
    XCTAssertFalse(error.isNotFound)
  }

  func testIsUnauthorized() {
    let error = StorageError(statusCode: "401", message: "bad jwt", error: "InvalidJWT")
    XCTAssertTrue(error.isUnauthorized)
  }

  func testIsEntityTooLarge() {
    let error = StorageError(statusCode: "413", message: "too large", error: "Payload too large")
    XCTAssertTrue(error.isEntityTooLarge)
  }
```

- [ ] **Step 2: Run tests — expect failure**

```bash
swift test --filter StorageErrorTests 2>&1 | tail -10
```

Expected: compile errors — `errorCode`, `isNotFound`, etc. not found.

- [ ] **Step 3: Add `StorageErrorCode` and the extension to `Sources/Storage/StorageError.swift`**

Append after the closing `}` of the `StorageError: LocalizedError` extension:

```swift
// MARK: - StorageErrorCode

/// A typed code identifying the specific error returned by the Storage server.
///
/// Known server error strings are exposed as static constants. Because the server may return
/// codes not listed here, the type is open-ended: any unrecognised string is representable
/// without breaking existing `switch` statements.
public struct StorageErrorCode: RawRepresentable, Sendable, Hashable {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.init(rawValue: rawValue) }
}

extension StorageErrorCode {
  /// Fallback used when the server returns an unrecognised code or a non-JSON body.
  public static let unknown = StorageErrorCode("unknown")

  // Authentication / authorisation
  public static let invalidJWT = StorageErrorCode("InvalidJWT")
  public static let unauthorized = StorageErrorCode("Unauthorized")

  // Object / bucket
  /// The requested object does not exist.
  public static let objectNotFound = StorageErrorCode("not_found")
  /// The requested bucket does not exist.
  public static let bucketNotFound = StorageErrorCode("Bucket not found")
  /// An object at the given path already exists and upsert was not requested.
  public static let objectAlreadyExists = StorageErrorCode("Duplicate")
  /// A bucket with the given name already exists.
  /// Note: the server uses the same "Duplicate" wire value for both object and bucket conflicts.
  public static let bucketAlreadyExists = StorageErrorCode("Duplicate")
  public static let invalidBucketName = StorageErrorCode("Invalid Input")

  // Upload
  public static let entityTooLarge = StorageErrorCode("Payload too large")
  public static let invalidMimeType = StorageErrorCode("invalid_mime_type")
}

// MARK: - StorageError convenience

extension StorageError {
  /// A typed error code derived from the server's `error` field.
  /// Returns `.unknown` when `error` is `nil`.
  public var errorCode: StorageErrorCode {
    guard let error else { return .unknown }
    return StorageErrorCode(rawValue: error)
  }

  /// `true` when the error indicates the requested object or bucket does not exist (404).
  public var isNotFound: Bool {
    errorCode == .objectNotFound || errorCode == .bucketNotFound
  }

  /// `true` when the error indicates the caller is not authenticated or authorised (401/403).
  public var isUnauthorized: Bool {
    errorCode == .unauthorized || errorCode == .invalidJWT
  }

  /// `true` when the uploaded file exceeds the configured size limit (413).
  public var isEntityTooLarge: Bool {
    errorCode == .entityTooLarge
  }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
swift test --filter StorageErrorTests 2>&1 | tail -10
```

Expected: All tests pass.

- [ ] **Step 5: Format and commit**

```bash
make format
git add Sources/Storage/StorageError.swift Tests/StorageTests/StorageErrorTests.swift
git commit -m "feat(storage): add StorageErrorCode and StorageError.errorCode computed property"
```

---

### Task 3: Consolidate BucketOptions + TransformOptions into Types.swift

This is a file-move refactoring. No API changes. Tests must pass before and after.

**Files:**
- Modify: `Sources/Storage/Types.swift` (append moved content)
- Delete: `Sources/Storage/BucketOptions.swift`
- Delete: `Sources/Storage/TransformOptions.swift`
- Modify: `Sources/Storage/Exports.swift` (remove exports of deleted files if any)

**Interfaces:**
- Consumes: existing `BucketOptions`, `TransformOptions`
- Produces: same types, same API, now in `Types.swift`

- [ ] **Step 1: Verify tests currently pass (baseline)**

```bash
swift test --filter StorageTests 2>&1 | tail -5
```

Expected: all pass.

- [ ] **Step 2: Move `BucketOptions` into `Types.swift`**

Append the entire content of `Sources/Storage/BucketOptions.swift` to `Sources/Storage/Types.swift`, removing the `import Foundation` line (it's already in `Types.swift`). Keep the struct exactly as-is — no changes yet.

Then delete `Sources/Storage/BucketOptions.swift`:
```bash
rm Sources/Storage/BucketOptions.swift
```

- [ ] **Step 3: Move `TransformOptions` into `Types.swift`**

Append the entire content of `Sources/Storage/TransformOptions.swift` to `Sources/Storage/Types.swift`, removing the `import Foundation` line. Keep it exactly as-is.

Then delete `Sources/Storage/TransformOptions.swift`:
```bash
rm Sources/Storage/TransformOptions.swift
```

- [ ] **Step 4: Check and update `Exports.swift`**

Open `Sources/Storage/Exports.swift`. If it re-exports `BucketOptions` or `TransformOptions` by referencing those module files, verify it still compiles. (The types still exist in `Types.swift` so no export changes are needed.)

- [ ] **Step 5: Run tests — expect pass**

```bash
swift test --filter StorageTests 2>&1 | tail -5
```

Expected: all pass (same types, just different source file location).

- [ ] **Step 6: Format and commit**

```bash
make format
git add Sources/Storage/Types.swift
git rm Sources/Storage/BucketOptions.swift Sources/Storage/TransformOptions.swift
git commit -m "refactor(storage): consolidate BucketOptions and TransformOptions into Types.swift"
```

---

### Task 4: Evolve TransformOptions field types

Change `resize: String?` → `ResizeMode?` and `format: String?` → `ImageFormat?`. `ExpressibleByStringLiteral` means existing string-literal code compiles unchanged. Tests must be updated since field type changes from `String?` to a struct.

**Files:**
- Modify: `Sources/Storage/Types.swift` (`TransformOptions` section)
- Modify: `Tests/StorageTests/TransformOptionsTests.swift`

**Interfaces:**
- Consumes: `ResizeMode`, `ImageFormat` from Task 1
- Produces: `TransformOptions.resize: ResizeMode?`, `TransformOptions.format: ImageFormat?`

- [ ] **Step 1: Update field types in `TransformOptions` in `Types.swift`**

In the `TransformOptions` struct (now in `Types.swift`), change:
```swift
// Before
public var resize: String?
public var format: String?

public init(
  width: Int? = nil,
  height: Int? = nil,
  resize: String? = nil,
  quality: Int? = nil,
  format: String? = nil
)
```

To:
```swift
// After
public var resize: ResizeMode?
public var format: ImageFormat?

public init(
  width: Int? = nil,
  height: Int? = nil,
  resize: ResizeMode? = nil,
  quality: Int? = nil,
  format: ImageFormat? = nil
)
```

The `queryItems` computed var passes `resize` and `format` as `.rawValue` already (they encode to the same string). No changes needed there since `ResizeMode`/`ImageFormat` encode their `rawValue` string.

Wait — the existing `queryItems` code appends:
```swift
items.append(URLQueryItem(name: "resize", value: resize))
items.append(URLQueryItem(name: "format", value: format))
```

After the type change, `resize` is `ResizeMode?` not `String?`. Update those lines to use `.rawValue`:
```swift
if let resize {
  items.append(URLQueryItem(name: "resize", value: resize.rawValue))
}
if let format {
  items.append(URLQueryItem(name: "format", value: format.rawValue))
}
```

- [ ] **Step 2: Update `Tests/StorageTests/TransformOptionsTests.swift`**

The tests that compare `options.resize` and `options.format` to `String` literals must be updated. Replace the following in the file:

```swift
// BEFORE — won't compile after type change
XCTAssertNil(options.resize)
XCTAssertFalse(TransformOptions(resize: "cover").isEmpty)
XCTAssertFalse(TransformOptions(format: "webp").isEmpty)
XCTAssertEqual(options.resize, "cover")
XCTAssertEqual(options.format, "webp")

// AFTER
XCTAssertNil(options.resize)
XCTAssertFalse(TransformOptions(resize: "cover").isEmpty)   // still compiles — ExpressibleByStringLiteral
XCTAssertFalse(TransformOptions(format: "webp").isEmpty)    // still compiles — ExpressibleByStringLiteral
XCTAssertEqual(options.resize, ResizeMode.cover)             // compare typed value
XCTAssertEqual(options.format, ImageFormat.webp)             // compare typed value
```

In `testCustomInitialization`, change:
```swift
// BEFORE
XCTAssertEqual(options.resize, "cover")
XCTAssertEqual(options.format, "webp")
// AFTER
XCTAssertEqual(options.resize, .cover)
XCTAssertEqual(options.format, .webp)
```

In `testQueryItemsGeneration`, the query items still produce `"cover"` and `"webp"` strings — no change needed there.

- [ ] **Step 3: Run tests — expect pass**

```bash
swift test --filter TransformOptionsTests 2>&1 | tail -10
```

Expected: all pass.

- [ ] **Step 4: Format and commit**

```bash
make format
git add Sources/Storage/Types.swift Tests/StorageTests/TransformOptionsTests.swift
git commit -m "feat(storage): evolve TransformOptions.resize to ResizeMode? and format to ImageFormat?"
```

---

### Task 5: Evolve SortBy.order field type

Change `SortBy.order: String?` → `SortOrder?`.

**Files:**
- Modify: `Sources/Storage/Types.swift` (`SortBy` struct)
- Modify: `Tests/StorageTests/StorageFileAPITests.swift` (if it directly compares `order` to a string) or create a targeted test

**Interfaces:**
- Consumes: `SortOrder` from Task 1
- Produces: `SortBy.order: SortOrder?`

- [ ] **Step 1: Check for tests that compare `SortBy.order` to a `String`**

```bash
grep -rn "\.order" Tests/StorageTests/ | grep -v ".swift:" | head -20
grep -rn "sortBy\|SortBy\|\.order" Tests/StorageTests/ | head -20
```

Note any tests that assign or compare `order` to a `String` literal — those will still compile (via `ExpressibleByStringLiteral`) but comparisons like `XCTAssertEqual(sortBy.order, "asc")` will fail to compile since `String` ≠ `SortOrder`.

- [ ] **Step 2: Update `SortBy` in `Types.swift`**

Change:
```swift
// Before
public struct SortBy: Encodable, Sendable {
  public var column: String?
  public var order: String?

  public init(column: String? = nil, order: String? = nil) {
    self.column = column
    self.order = order
  }
}
```

To:
```swift
// After
public struct SortBy: Encodable, Sendable {
  public var column: String?
  public var order: SortOrder?

  public init(column: String? = nil, order: SortOrder? = nil) {
    self.column = column
    self.order = order
  }
}
```

The `Encodable` synthesis encodes `order` using `SortOrder`'s `Codable` conformance (from Task 1), which encodes the `rawValue` string. Wire format is unchanged.

- [ ] **Step 3: Fix any broken test comparisons found in Step 1**

If you found tests comparing `sortBy.order` to a string like `"asc"`, change them to compare to `SortOrder.ascending` or check `.rawValue`:

```swift
// Before
XCTAssertEqual(sortBy.order, "asc")
// After
XCTAssertEqual(sortBy.order, .ascending)
// Or: XCTAssertEqual(sortBy.order?.rawValue, "asc")
```

- [ ] **Step 4: Run tests — expect pass**

```bash
swift test --filter StorageTests 2>&1 | tail -10
```

Expected: all pass.

- [ ] **Step 5: Format and commit**

```bash
make format
git add Sources/Storage/Types.swift
git commit -m "feat(storage): evolve SortBy.order to SortOrder?"
```

---

### Task 6: BucketOptions rename + type change

Rename `public:` → `isPublic:`, change `fileSizeLimit: String?` → `StorageByteCount?`. Add deprecated bridges. Update `StorageBucketApi.BucketParameters` to send `Int64` instead of `String` for `fileSizeLimit` (also fixes a wire-format bug).

**Files:**
- Modify: `Sources/Storage/Types.swift` (`BucketOptions` section)
- Modify: `Sources/Storage/StorageBucketApi.swift`
- Modify: `Tests/StorageTests/BucketOptionsTests.swift`

**Interfaces:**
- Consumes: `StorageByteCount` from Task 1
- Produces:
  - `BucketOptions.isPublic: Bool` (renamed from `public`)
  - `BucketOptions.fileSizeLimit: StorageByteCount?` (was `String?`)
  - Deprecated `BucketOptions.public` computed property bridge
  - Deprecated `BucketOptions.init(public:fileSizeLimit:String?:allowedMimeTypes:)` bridge

- [ ] **Step 1: Add new tests to `Tests/StorageTests/BucketOptionsTests.swift`**

The existing tests use the old API and will still compile (via deprecated bridges). Add new tests below the existing ones, inside the same `BucketOptionsTests` class:

```swift
  func testIsPublicRename() {
    let options = BucketOptions(isPublic: true)
    XCTAssertTrue(options.isPublic)
  }

  func testFileSizeLimitStorageByteCount() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: .megabytes(5))
    XCTAssertEqual(options.fileSizeLimit?.bytes, 5_242_880)
  }

  func testFileSizeLimitIntegerLiteral() {
    let options = BucketOptions(fileSizeLimit: 10_485_760)
    XCTAssertEqual(options.fileSizeLimit?.bytes, 10_485_760)
  }

  func testDeprecatedPublicBridge() {
    var options = BucketOptions(isPublic: false)
    options.public = true  // deprecated setter
    XCTAssertTrue(options.isPublic)
    XCTAssertTrue(options.public)  // deprecated getter
  }

  func testDeprecatedStringFileSizeLimitBridge() {
    let options = BucketOptions(public: false, fileSizeLimit: "5242880")
    XCTAssertEqual(options.fileSizeLimit?.bytes, 5_242_880)
  }

  func testDeprecatedStringFileSizeLimitNil() {
    let options = BucketOptions(public: false, fileSizeLimit: nil)
    XCTAssertNil(options.fileSizeLimit)
  }
```

- [ ] **Step 2: Run new tests — expect compile failure**

```bash
swift test --filter BucketOptionsTests 2>&1 | tail -10
```

Expected: compile errors for `isPublic`, `StorageByteCount`.

- [ ] **Step 3: Update `BucketOptions` in `Types.swift`**

Replace the existing `BucketOptions` struct with:

```swift
/// Options used when creating or updating a Storage bucket.
public struct BucketOptions: Sendable {
  /// Whether the bucket is publicly accessible without an authorization token.
  public var isPublic: Bool

  /// The maximum file size allowed for uploads.
  ///
  /// Use ``StorageByteCount`` factory methods: `.megabytes(5)`, `.gigabytes(1)`,
  /// or an integer literal for raw bytes. `nil` means no per-bucket limit.
  public var fileSizeLimit: StorageByteCount?

  /// MIME types accepted during upload. Each entry can be exact (`"image/png"`) or
  /// a wildcard (`"image/*"`). `nil` allows all MIME types.
  public var allowedMimeTypes: [String]?

  public init(
    isPublic: Bool = false,
    fileSizeLimit: StorageByteCount? = nil,
    allowedMimeTypes: [String]? = nil
  ) {
    self.isPublic = isPublic
    self.fileSizeLimit = fileSizeLimit
    self.allowedMimeTypes = allowedMimeTypes
  }

  // MARK: Deprecated bridges

  @available(*, deprecated, renamed: "isPublic")
  public var `public`: Bool {
    get { isPublic }
    set { isPublic = newValue }
  }

  @available(*, deprecated, renamed: "init(isPublic:fileSizeLimit:allowedMimeTypes:)")
  public init(
    public isPublic: Bool = false,
    fileSizeLimit: String? = nil,
    allowedMimeTypes: [String]? = nil
  ) {
    self.init(
      isPublic: isPublic,
      fileSizeLimit: fileSizeLimit.flatMap { Int64($0).map(StorageByteCount.init) },
      allowedMimeTypes: allowedMimeTypes
    )
  }
}
```

- [ ] **Step 4: Update `StorageBucketApi.swift`**

The internal `BucketParameters` struct and the two call sites must be updated.

Change `BucketParameters`:
```swift
// Before
struct BucketParameters: Encodable {
  var id: String
  var name: String
  var `public`: Bool
  var fileSizeLimit: String?
  var allowedMimeTypes: [String]?
}

// After
struct BucketParameters: Encodable {
  var id: String
  var name: String
  var `public`: Bool
  var fileSizeLimit: Int64?
  var allowedMimeTypes: [String]?
}
```

Update `createBucket`:
```swift
// Before
BucketParameters(
  id: id,
  name: id,
  public: options.public,
  fileSizeLimit: options.fileSizeLimit,
  allowedMimeTypes: options.allowedMimeTypes
)

// After
BucketParameters(
  id: id,
  name: id,
  public: options.isPublic,
  fileSizeLimit: options.fileSizeLimit?.bytes,
  allowedMimeTypes: options.allowedMimeTypes
)
```

Update `updateBucket` the same way (same change in the second `BucketParameters(...)` call).

- [ ] **Step 5: Run tests — expect pass**

```bash
swift test --filter StorageTests 2>&1 | tail -10
```

Expected: all pass, including new `BucketOptionsTests`.

- [ ] **Step 6: Format and commit**

```bash
make format
git add Sources/Storage/Types.swift Sources/Storage/StorageBucketApi.swift Tests/StorageTests/BucketOptionsTests.swift
git commit -m "feat(storage): rename BucketOptions.public to isPublic, fileSizeLimit to StorageByteCount"
```

---

### Task 7: DownloadBehavior overloads

Add `DownloadBehavior?` overloads to `createSignedURL`, `createSignedURLs`, and `getPublicURL`. Mark the `Bool` overloads deprecated. Mark the existing `String?` overloads with `@_disfavoredOverload` to prevent ambiguity when callers omit the parameter (both `String?` and `DownloadBehavior?` have a `nil` default).

**Files:**
- Modify: `Sources/Storage/StorageFileApi.swift`
- Create: `Tests/StorageTests/DownloadBehaviorTests.swift`

**Interfaces:**
- Consumes: `DownloadBehavior` from Task 1 (`.queryValue` internal property)
- Produces:
  - `createSignedURL(path:expiresIn:download:DownloadBehavior?:transform:cacheNonce:)` async throws → URL
  - `createSignedURLs(paths:expiresIn:download:DownloadBehavior?:cacheNonce:)` async throws → [SignedURLResult]
  - `getPublicURL(path:download:DownloadBehavior?:options:cacheNonce:)` throws → URL
  - `Bool` overloads deprecated

- [ ] **Step 1: Create `Tests/StorageTests/DownloadBehaviorTests.swift`**

Use the `SupabaseStorageClient.test(supabaseURL:apiKey:)` helper (defined in `Tests/StorageTests/SupabaseStorageClient+Test.swift`) to get a `StorageFileApi` via `.from("bucket")`:

```swift
import Testing
import Foundation
import Storage

@Suite struct DownloadBehaviorURLTests {
  let bucket = SupabaseStorageClient.test(
    supabaseURL: "http://localhost:54321/storage/v1",
    apiKey: "test-api-key"
  ).from("test-bucket")

  @Test func getPublicURL_noDownload() throws {
    let url = try bucket.getPublicURL(path: "image.png")
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let downloadItem = components?.queryItems?.first { $0.name == "download" }
    #expect(downloadItem == nil)
  }

  @Test func getPublicURL_withOriginalName() throws {
    let url = try bucket.getPublicURL(path: "image.png", download: .withOriginalName)
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let downloadItem = components?.queryItems?.first { $0.name == "download" }
    #expect(downloadItem?.value == "")
  }

  @Test func getPublicURL_namedDownload() throws {
    let url = try bucket.getPublicURL(path: "image.png", download: .named("photo.jpg"))
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let downloadItem = components?.queryItems?.first { $0.name == "download" }
    #expect(downloadItem?.value == "photo.jpg")
  }

  @Test func getPublicURL_nilDownload() throws {
    let url = try bucket.getPublicURL(path: "image.png", download: Optional<DownloadBehavior>.none)
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let downloadItem = components?.queryItems?.first { $0.name == "download" }
    #expect(downloadItem == nil)
  }
}
```

- [ ] **Step 2: Run new tests — expect compile failure**

```bash
swift test --filter DownloadBehaviorURLTests 2>&1 | tail -10
```

Expected: compile errors since new `getPublicURL(path:download:DownloadBehavior?:...)` doesn't exist yet.

- [ ] **Step 3: Add `@_disfavoredOverload` to the existing `String?` overloads in `StorageFileApi.swift`**

Find and annotate the three `String?` overloads:

```swift
// createSignedURL — add @_disfavoredOverload
@_disfavoredOverload
public func createSignedURL(
  path: String,
  expiresIn: Int,
  download: String? = nil,
  transform: TransformOptions? = nil,
  cacheNonce: String? = nil
) async throws -> URL { ... }

// createSignedURLs — add @_disfavoredOverload
@_disfavoredOverload
public func createSignedURLs(
  paths: [String],
  expiresIn: Int,
  download: String? = nil,
  cacheNonce: String? = nil
) async throws -> [SignedURLResult] { ... }

// getPublicURL — add @_disfavoredOverload
@_disfavoredOverload
public func getPublicURL(
  path: String,
  download: String? = nil,
  options: TransformOptions? = nil,
  cacheNonce: String? = nil
) throws -> URL { ... }
```

- [ ] **Step 4: Add new `DownloadBehavior?` overloads and deprecate `Bool` overloads**

Add the three new overloads immediately after their `String?` counterparts, and mark the existing `Bool` overloads `@available(*, deprecated)`:

```swift
/// Creates a signed URL. Use a signed URL to share a file for a fixed amount of time.
/// - Parameters:
///   - path: The file path, including the current file name.
///   - expiresIn: The number of seconds until the signed URL expires.
///   - download: Controls the `Content-Disposition` header. Pass `.withOriginalName` to
///     trigger a download using the original filename, or `.named("custom.pdf")` for a
///     custom name. `nil` (default) serves the file inline.
///   - transform: Transform the asset before serving it to the client.
///   - cacheNonce: A nonce value appended as a `cacheNonce` query parameter for cache invalidation.
public func createSignedURL(
  path: String,
  expiresIn: Int,
  download: DownloadBehavior? = nil,
  transform: TransformOptions? = nil,
  cacheNonce: String? = nil
) async throws -> URL {
  try await createSignedURL(
    path: path,
    expiresIn: expiresIn,
    download: download?.queryValue,
    transform: transform,
    cacheNonce: cacheNonce
  )
}

@available(*, deprecated, message: "Use download: DownloadBehavior? instead. Pass .withOriginalName to trigger download.")
public func createSignedURL(
  path: String,
  expiresIn: Int,
  download: Bool,
  transform: TransformOptions? = nil,
  cacheNonce: String? = nil
) async throws -> URL {
  try await createSignedURL(
    path: path,
    expiresIn: expiresIn,
    download: download ? DownloadBehavior.withOriginalName : nil,
    transform: transform,
    cacheNonce: cacheNonce
  )
}
```

```swift
/// Creates multiple signed URLs.
/// - Parameters:
///   - paths: The file paths to be downloaded.
///   - expiresIn: The number of seconds until the signed URLs expire.
///   - download: Controls the `Content-Disposition` header for all URLs.
///   - cacheNonce: A nonce value appended as a `cacheNonce` query parameter for cache invalidation.
public func createSignedURLs(
  paths: [String],
  expiresIn: Int,
  download: DownloadBehavior? = nil,
  cacheNonce: String? = nil
) async throws -> [SignedURLResult] {
  try await createSignedURLs(
    paths: paths,
    expiresIn: expiresIn,
    download: download?.queryValue,
    cacheNonce: cacheNonce
  )
}

@available(*, deprecated, message: "Use download: DownloadBehavior? instead.")
public func createSignedURLs(
  paths: [String],
  expiresIn: Int,
  download: Bool,
  cacheNonce: String? = nil
) async throws -> [SignedURLResult] {
  try await createSignedURLs(
    paths: paths,
    expiresIn: expiresIn,
    download: download ? DownloadBehavior.withOriginalName : nil,
    cacheNonce: cacheNonce
  )
}
```

```swift
/// Gets the URL for an asset in a public bucket.
/// - Parameters:
///   - path: The path and name of the file.
///   - download: Controls the `Content-Disposition` header.
///   - options: Transform the asset before retrieving it.
///   - cacheNonce: A nonce value appended as a `cacheNonce` query parameter for cache invalidation.
public func getPublicURL(
  path: String,
  download: DownloadBehavior? = nil,
  options: TransformOptions? = nil,
  cacheNonce: String? = nil
) throws -> URL {
  try getPublicURL(
    path: path,
    download: download?.queryValue,
    options: options,
    cacheNonce: cacheNonce
  )
}

@available(*, deprecated, message: "Use download: DownloadBehavior? instead.")
public func getPublicURL(
  path: String,
  download: Bool,
  options: TransformOptions? = nil,
  cacheNonce: String? = nil
) throws -> URL {
  try getPublicURL(
    path: path,
    download: download ? DownloadBehavior.withOriginalName : nil,
    options: options,
    cacheNonce: cacheNonce
  )
}
```

- [ ] **Step 5: Run tests — expect pass**

```bash
swift test --filter StorageTests 2>&1 | tail -10
```

Expected: all tests pass including `DownloadBehaviorURLTests`.

- [ ] **Step 6: Run full xcodebuild test suite**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild
```

Expected: all tests pass.

- [ ] **Step 7: Format and commit**

```bash
make format
git add Sources/Storage/StorageFileApi.swift Tests/StorageTests/DownloadBehaviorTests.swift
git commit -m "feat(storage): add DownloadBehavior overloads for createSignedURL, createSignedURLs, getPublicURL"
```

---

### Task 8: Open the PR

- [ ] **Step 1: Verify full test suite passes**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild
```

- [ ] **Step 2: Create PR**

```bash
gh pr create \
  --base main \
  --title "feat(storage): backport typed value types and API ergonomics from v3" \
  --body "$(cat <<'EOF'
## Summary

Backports typed value types and API ergonomics from the v3 branch into v2. Zero breaking changes — all existing call sites compile unchanged.

### New types
- `StorageByteCount` — value type for file sizes (`.megabytes(5)`, int literal)
- `ResizeMode` — typed resize mode with `ExpressibleByStringLiteral`
- `ImageFormat` — typed image format with `ExpressibleByStringLiteral`
- `SortOrder` — typed sort direction with `ExpressibleByStringLiteral`
- `DownloadBehavior` — replaces `Bool` download parameter
- `UploadMethod` — `.auto / .multipart / .resumable` (used in PR 3)
- `StorageErrorCode` — typed error code with `StorageError.errorCode` computed property

### Evolved existing types
- `TransformOptions.resize: String?` → `ResizeMode?` (string literals still work)
- `TransformOptions.format: String?` → `ImageFormat?` (string literals still work)
- `SortBy.order: String?` → `SortOrder?` (string literals still work)
- `BucketOptions.public: Bool` → `isPublic: Bool` (deprecated `public` bridge kept)
- `BucketOptions.fileSizeLimit: String?` → `StorageByteCount?` (deprecated `String?` bridge kept)
- Also fixes a wire-format bug: `fileSizeLimit` was being sent as a JSON string; it now correctly sends a JSON number

### Convenience
- `StorageError.errorCode: StorageErrorCode` — computed from `error` field
- `StorageError.isNotFound / isUnauthorized / isEntityTooLarge`
- `createSignedURL / createSignedURLs / getPublicURL` gain `DownloadBehavior?` overloads; `Bool` overloads deprecated

### File consolidation
- `BucketOptions.swift` and `TransformOptions.swift` merged into `Types.swift`

## Test plan
- [ ] All existing Storage tests pass unchanged
- [ ] `ValueTypesTests` (new, Swift Testing) cover all 7 new types
- [ ] `StorageErrorTests` extended with `errorCode`, `isNotFound`, `isUnauthorized`, `isEntityTooLarge`
- [ ] `BucketOptionsTests` extended with `isPublic`, `StorageByteCount`, deprecated bridges
- [ ] `TransformOptionsTests` updated for typed field comparisons
- [ ] `DownloadBehaviorTests` (new, Swift Testing) cover URL generation
- [ ] Full xcodebuild suite passes on iOS
EOF
)"
```
