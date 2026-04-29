# Storage API v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Storage module API v2 improvements — typed value types, naming fixes, method-signature consolidation, and opt-in upload progress reporting.

**Architecture:** New types land in `Sources/Storage/Types.swift`. Method changes are in `StorageFileAPI.swift` and `StorageClient.swift`. Progress reporting uses a private `UploadProgressDelegate` scoped per upload task — no global session delegate required.

**Spec:** `docs/superpowers/specs/2026-04-29-storage-api-improvements-design.md`

**Tech stack:** Swift 6.1+, XCTest, InlineSnapshotTesting, Mocker

**Test command:** `swift test --filter StorageTests`

---

## File map

| File | What changes |
|---|---|
| `Sources/Storage/Types.swift` | Add `ResizeMode`, `ImageFormat`, `SortOrder`, `StorageByteCount`, `DownloadBehavior`, `UploadProgress`; update `TransformOptions`, `SortBy`, `BucketOptions`, `FileOptions`, `SearchOptions`; rename `FileObjectV2` → `FileInfo`; remove `SignedURL` |
| `Sources/Storage/StorageFileAPI.swift` | Update `createSignedURL`, `createSignedURLs`, `getPublicURL`, `upload`, `update`, `uploadToSignedURL`, `info`; add `UploadProgressDelegate`; update `makeSignedURL`, `_uploadOrUpdate`, `uploadMultipart`, `multipartHeaders`, `_uploadToSignedURL` |
| `Sources/Storage/StorageClient.swift` | Update `BucketParameters` struct (CodingKeys + `isPublic` + `fileSizeLimit: Int64?`) |
| `Tests/StorageTests/ValueTypesTests.swift` | New — tests for `ResizeMode`, `ImageFormat`, `SortOrder`, `DownloadBehavior` |
| `Tests/StorageTests/StorageByteCountTests.swift` | New — tests for `StorageByteCount` factory methods |
| `Tests/StorageTests/UploadProgressTests.swift` | New — tests for `UploadProgress` |
| `Tests/StorageTests/TransformOptionsTests.swift` | Update string literals → typed values |
| `Tests/StorageTests/BucketOptionsTests.swift` | Update `public`→`isPublic`, `fileSizeLimit` |
| `Tests/StorageTests/FileOptionsTests.swift` | Remove `duplex`/`headers` references |
| `Tests/StorageTests/StorageFileAPITests.swift` | Update `expiresIn`, `download`, `info` return type |
| `Tests/StorageTests/StorageBucketAPITests.swift` | Update `BucketOptions` call sites |
| `Tests/StorageTests/SupabaseStorageTests.swift` | Update `getPublicURL`, `createSignedURLs` call sites |

---

## Task 1: Add ResizeMode, ImageFormat, SortOrder

**Files:**
- Modify: `Sources/Storage/Types.swift`
- Create: `Tests/StorageTests/ValueTypesTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/StorageTests/ValueTypesTests.swift`:

```swift
import XCTest
@testable import Storage

final class ValueTypesTests: XCTestCase {

  // MARK: - ResizeMode

  func testResizeMode_knownValues() {
    XCTAssertEqual(ResizeMode.cover.rawValue, "cover")
    XCTAssertEqual(ResizeMode.contain.rawValue, "contain")
    XCTAssertEqual(ResizeMode.fill.rawValue, "fill")
  }

  func testResizeMode_customValue() {
    let custom = ResizeMode(rawValue: "fit")
    XCTAssertEqual(custom.rawValue, "fit")
  }

  func testResizeMode_stringLiteral() {
    let mode: ResizeMode = "cover"
    XCTAssertEqual(mode, .cover)
  }

  // MARK: - ImageFormat

  func testImageFormat_knownValues() {
    XCTAssertEqual(ImageFormat.origin.rawValue, "origin")
    XCTAssertEqual(ImageFormat.webp.rawValue, "webp")
    XCTAssertEqual(ImageFormat.avif.rawValue, "avif")
  }

  func testImageFormat_customValue() {
    let custom = ImageFormat(rawValue: "jpeg")
    XCTAssertEqual(custom.rawValue, "jpeg")
  }

  func testImageFormat_stringLiteral() {
    let format: ImageFormat = "webp"
    XCTAssertEqual(format, .webp)
  }

  // MARK: - SortOrder

  func testSortOrder_knownValues() {
    XCTAssertEqual(SortOrder.ascending.rawValue, "asc")
    XCTAssertEqual(SortOrder.descending.rawValue, "desc")
  }

  func testSortOrder_encodes_asRawValue() throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(SortOrder.ascending)
    let string = String(data: data, encoding: .utf8)
    XCTAssertEqual(string, "\"asc\"")
  }

  func testSortOrder_decodes_fromRawValue() throws {
    let data = "\"desc\"".data(using: .utf8)!
    let order = try JSONDecoder().decode(SortOrder.self, from: data)
    XCTAssertEqual(order, .descending)
  }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
swift test --filter ValueTypesTests 2>&1 | head -20
```

Expected: `error: cannot find type 'ResizeMode' in scope`

- [ ] **Step 3: Add the three types to Types.swift**

Add before the `TransformOptions` declaration in `Sources/Storage/Types.swift`:

```swift
/// Resize mode for on-the-fly image transformation.
///
/// Follows the `FunctionRegion` pattern: open to custom backend values without
/// requiring an SDK update.
public struct ResizeMode: RawRepresentable, Hashable, Sendable {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Fill the target dimensions, cropping any overflow. Default behaviour.
  public static let cover   = ResizeMode(rawValue: "cover")
  /// Fit the image within the target dimensions, letterboxing if needed.
  public static let contain = ResizeMode(rawValue: "contain")
  /// Stretch the image to exactly fill the target dimensions.
  public static let fill    = ResizeMode(rawValue: "fill")
}

extension ResizeMode: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension ResizeMode: Encodable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

extension ResizeMode: Decodable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }
}

/// Output format for on-the-fly image transformation.
///
/// Follows the `FunctionRegion` pattern: open to custom backend values.
public struct ImageFormat: RawRepresentable, Hashable, Sendable {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Preserve the original file format.
  public static let origin = ImageFormat(rawValue: "origin")
  public static let webp   = ImageFormat(rawValue: "webp")
  public static let avif   = ImageFormat(rawValue: "avif")
}

extension ImageFormat: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension ImageFormat: Encodable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

extension ImageFormat: Decodable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }
}

/// Sort direction for ``StorageFileAPI/list(path:options:)`` results.
///
/// Follows the `FunctionRegion` pattern: open to custom backend values.
public struct SortOrder: RawRepresentable, Hashable, Sendable {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let ascending  = SortOrder(rawValue: "asc")
  public static let descending = SortOrder(rawValue: "desc")
}

extension SortOrder: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension SortOrder: Encodable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

extension SortOrder: Decodable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
swift test --filter ValueTypesTests
```

Expected: `Test Suite 'ValueTypesTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/Storage/Types.swift Tests/StorageTests/ValueTypesTests.swift
git commit -m "feat(storage): add ResizeMode, ImageFormat, SortOrder typed value types"
```

---

## Task 2: Add StorageByteCount

**Files:**
- Modify: `Sources/Storage/Types.swift`
- Create: `Tests/StorageTests/StorageByteCountTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/StorageTests/StorageByteCountTests.swift`:

```swift
import XCTest
@testable import Storage

final class StorageByteCountTests: XCTestCase {

  func testBytes() {
    XCTAssertEqual(StorageByteCount.bytes(1024).bytes, 1024)
  }

  func testKilobytes() {
    XCTAssertEqual(StorageByteCount.kilobytes(1).bytes, 1_024)
    XCTAssertEqual(StorageByteCount.kilobytes(10).bytes, 10_240)
  }

  func testMegabytes() {
    XCTAssertEqual(StorageByteCount.megabytes(1).bytes, 1_048_576)
    XCTAssertEqual(StorageByteCount.megabytes(5).bytes, 5_242_880)
  }

  func testGigabytes() {
    XCTAssertEqual(StorageByteCount.gigabytes(1).bytes, 1_073_741_824)
  }

  func testIntegerLiteral() {
    let count: StorageByteCount = 5_242_880
    XCTAssertEqual(count.bytes, 5_242_880)
  }

  func testEquality() {
    XCTAssertEqual(StorageByteCount.megabytes(1), StorageByteCount.kilobytes(1024))
    XCTAssertNotEqual(StorageByteCount.megabytes(1), StorageByteCount.megabytes(2))
  }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
swift test --filter StorageByteCountTests 2>&1 | head -20
```

Expected: `error: cannot find type 'StorageByteCount' in scope`

- [ ] **Step 3: Add StorageByteCount to Types.swift**

Add before the `BucketOptions` declaration in `Sources/Storage/Types.swift`:

```swift
/// A type-safe byte count, modelled after `Swift.Duration`.
///
/// Uses `Int64` backing to avoid the precision loss of `Measurement<UnitInformationStorage>`
/// and sidesteps the SI vs binary ambiguity of Foundation's `UnitInformationStorage`.
///
/// ## Example
///
/// ```swift
/// BucketOptions(isPublic: true, fileSizeLimit: .megabytes(5))
/// BucketOptions(isPublic: true, fileSizeLimit: .gigabytes(1))
/// BucketOptions(isPublic: true, fileSizeLimit: 5_242_880)  // raw bytes via integer literal
/// ```
public struct StorageByteCount: Sendable, Hashable {
  /// The raw byte count.
  public let bytes: Int64

  public init(_ bytes: Int64) { self.bytes = bytes }

  public static func bytes(_ value: Int64)     -> Self { Self(value) }
  public static func kilobytes(_ value: Int64) -> Self { Self(value * 1_024) }
  public static func megabytes(_ value: Int64) -> Self { Self(value * 1_024 * 1_024) }
  public static func gigabytes(_ value: Int64) -> Self { Self(value * 1_024 * 1_024 * 1_024) }
}

extension StorageByteCount: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int64) { self.init(value) }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
swift test --filter StorageByteCountTests
```

Expected: `Test Suite 'StorageByteCountTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/Storage/Types.swift Tests/StorageTests/StorageByteCountTests.swift
git commit -m "feat(storage): add StorageByteCount value type"
```

---

## Task 3: Add DownloadBehavior

**Files:**
- Modify: `Sources/Storage/Types.swift`
- Modify: `Tests/StorageTests/ValueTypesTests.swift`

- [ ] **Step 1: Add tests for DownloadBehavior**

Append to `Tests/StorageTests/ValueTypesTests.swift`:

```swift
  // MARK: - DownloadBehavior

  func testDownloadBehavior_download() {
    if case .download = DownloadBehavior.download { } else {
      XCTFail("Expected .download case")
    }
  }

  func testDownloadBehavior_downloadAs() {
    if case .downloadAs(let name) = DownloadBehavior.downloadAs("report.pdf") {
      XCTAssertEqual(name, "report.pdf")
    } else {
      XCTFail("Expected .downloadAs case")
    }
  }
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
swift test --filter ValueTypesTests 2>&1 | head -20
```

Expected: `error: cannot find type 'DownloadBehavior' in scope`

- [ ] **Step 3: Add DownloadBehavior to Types.swift**

Add after `SortOrder` in `Sources/Storage/Types.swift`:

```swift
/// Controls browser download behaviour for public and signed URLs.
///
/// Pass to ``StorageFileAPI/getPublicURL(path:download:options:cacheNonce:)``,
/// ``StorageFileAPI/createSignedURL(path:expiresIn:download:transform:cacheNonce:)``, or
/// ``StorageFileAPI/createSignedURLs(paths:expiresIn:download:cacheNonce:)``.
///
/// ## Example
///
/// ```swift
/// // Trigger download using the file's original filename
/// let url = try bucket.getPublicURL(path: "report.pdf", download: .download)
///
/// // Trigger download with a custom filename
/// let url = try bucket.getPublicURL(path: "report.pdf", download: .downloadAs("annual-2024.pdf"))
/// ```
public enum DownloadBehavior: Sendable {
  /// Trigger a browser download prompt using the file's original name.
  ///
  /// Wire format: appends `?download=` (empty string value) to the URL.
  case download

  /// Trigger a browser download prompt using a custom filename.
  ///
  /// Wire format: appends `?download=<filename>` to the URL.
  case downloadAs(String)
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
swift test --filter ValueTypesTests
```

Expected: `Test Suite 'ValueTypesTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/Storage/Types.swift Tests/StorageTests/ValueTypesTests.swift
git commit -m "feat(storage): add DownloadBehavior enum"
```

---

## Task 4: Update TransformOptions to use ResizeMode and ImageFormat

**Files:**
- Modify: `Sources/Storage/Types.swift`
- Modify: `Tests/StorageTests/TransformOptionsTests.swift`

- [ ] **Step 1: Update TransformOptionsTests to use typed values**

Replace the full content of `Tests/StorageTests/TransformOptionsTests.swift`:

```swift
import XCTest
@testable import Storage

final class TransformOptionsTests: XCTestCase {
  func testDefaultInitialization() {
    let options = TransformOptions()

    XCTAssertNil(options.width)
    XCTAssertNil(options.height)
    XCTAssertNil(options.resize)
    XCTAssertNil(options.quality)
    XCTAssertNil(options.format)
  }

  func testIsEmpty_defaultOptions() {
    XCTAssertTrue(TransformOptions().isEmpty)
  }

  func testIsEmpty_withWidth() {
    XCTAssertFalse(TransformOptions(width: 200).isEmpty)
  }

  func testIsEmpty_withHeight() {
    XCTAssertFalse(TransformOptions(height: 300).isEmpty)
  }

  func testIsEmpty_withResize() {
    XCTAssertFalse(TransformOptions(resize: .cover).isEmpty)
  }

  func testIsEmpty_withQuality() {
    XCTAssertFalse(TransformOptions(quality: 90).isEmpty)
  }

  func testIsEmpty_withFormat() {
    XCTAssertFalse(TransformOptions(format: .webp).isEmpty)
  }

  func testCustomInitialization() {
    let options = TransformOptions(
      width: 100,
      height: 200,
      resize: .cover,
      quality: 90,
      format: .webp
    )

    XCTAssertEqual(options.width, 100)
    XCTAssertEqual(options.height, 200)
    XCTAssertEqual(options.resize, .cover)
    XCTAssertEqual(options.quality, 90)
    XCTAssertEqual(options.format, .webp)
  }

  func testQueryItemsGeneration() {
    let options = TransformOptions(
      width: 100,
      height: 200,
      resize: .cover,
      quality: 90,
      format: .webp
    )

    let queryItems = options.queryItems

    XCTAssertEqual(queryItems.count, 5)
    XCTAssertEqual(queryItems[0].name, "width")
    XCTAssertEqual(queryItems[0].value, "100")
    XCTAssertEqual(queryItems[1].name, "height")
    XCTAssertEqual(queryItems[1].value, "200")
    XCTAssertEqual(queryItems[2].name, "resize")
    XCTAssertEqual(queryItems[2].value, "cover")
    XCTAssertEqual(queryItems[3].name, "quality")
    XCTAssertEqual(queryItems[3].value, "90")
    XCTAssertEqual(queryItems[4].name, "format")
    XCTAssertEqual(queryItems[4].value, "webp")
  }

  func testPartialQueryItemsGeneration() {
    let options = TransformOptions(width: 100, quality: 75)

    let queryItems = options.queryItems

    XCTAssertEqual(queryItems.count, 2)
    XCTAssertEqual(queryItems[0].name, "width")
    XCTAssertEqual(queryItems[0].value, "100")
    XCTAssertEqual(queryItems[1].name, "quality")
    XCTAssertEqual(queryItems[1].value, "75")
  }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
swift test --filter TransformOptionsTests 2>&1 | head -20
```

Expected: `error: cannot convert value of type 'ResizeMode' to expected argument type 'String'`

- [ ] **Step 3: Update TransformOptions in Types.swift**

Replace the `TransformOptions` struct:

```swift
/// Options for on-the-fly image transformation via the Supabase Storage image transformation API.
///
/// Use `TransformOptions` when calling
/// ``StorageFileAPI/download(path:options:query:cacheNonce:)`` or
/// ``StorageFileAPI/getPublicURL(path:download:options:cacheNonce:)`` to resize, reformat, or
/// adjust the quality of images before they are served to the client.
///
/// ## Example
///
/// ```swift
/// // Serve a 200×200 thumbnail, retaining aspect ratio, at 75% quality
/// let url = try storage.from("avatars").getPublicURL(
///   path: "user-123/avatar.png",
///   options: TransformOptions(width: 200, height: 200, resize: .contain, quality: 75)
/// )
/// ```
public struct TransformOptions: Encodable, Sendable {
  /// The target width of the transformed image in pixels.
  public var width: Int?

  /// The target height of the transformed image in pixels.
  public var height: Int?

  /// Controls how the image is resized to fit the target dimensions.
  public var resize: ResizeMode?

  /// The quality of the returned image, from `20` (lowest) to `100` (highest).
  ///
  /// Applies to lossy formats such as JPEG and WebP. Defaults to `80`.
  public var quality: Int?

  /// The output format for the transformed image.
  ///
  /// Use `.origin` to preserve the original format of the file.
  public var format: ImageFormat?

  public init(
    width: Int? = nil,
    height: Int? = nil,
    resize: ResizeMode? = nil,
    quality: Int? = nil,
    format: ImageFormat? = nil
  ) {
    self.width = width
    self.height = height
    self.resize = resize
    self.quality = quality
    self.format = format
  }

  var isEmpty: Bool {
    queryItems.isEmpty
  }

  var queryItems: [URLQueryItem] {
    var items = [URLQueryItem]()

    if let width {
      items.append(URLQueryItem(name: "width", value: String(width)))
    }

    if let height {
      items.append(URLQueryItem(name: "height", value: String(height)))
    }

    if let resize {
      items.append(URLQueryItem(name: "resize", value: resize.rawValue))
    }

    if let quality {
      items.append(URLQueryItem(name: "quality", value: String(quality)))
    }

    if let format {
      items.append(URLQueryItem(name: "format", value: format.rawValue))
    }

    return items
  }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
swift test --filter TransformOptionsTests
```

Expected: `Test Suite 'TransformOptionsTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/Storage/Types.swift Tests/StorageTests/TransformOptionsTests.swift
git commit -m "refactor(storage): update TransformOptions to use ResizeMode and ImageFormat"
```

---

## Task 5: Update SortBy to use SortOrder

**Files:**
- Modify: `Sources/Storage/Types.swift`
- Modify: `Tests/StorageTests/ValueTypesTests.swift`

- [ ] **Step 1: Add SortBy test**

Append to `Tests/StorageTests/ValueTypesTests.swift`:

```swift
  // MARK: - SortBy

  func testSortBy_encodesOrderAsRawValue() throws {
    let sortBy = SortBy(column: "name", order: .descending)
    let encoder = JSONEncoder()
    let data = try encoder.encode(sortBy)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["column"] as? String, "name")
    XCTAssertEqual(json["order"] as? String, "desc")
  }
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
swift test --filter ValueTypesTests 2>&1 | head -20
```

Expected: `error: cannot convert value of type 'SortOrder' to expected argument type 'String?'`

- [ ] **Step 3: Update SortBy in Types.swift**

Replace the `SortBy` struct:

```swift
/// Defines the sort column and direction for a ``StorageFileAPI/list(path:options:)`` response.
///
/// ## Example
///
/// ```swift
/// let options = SearchOptions(sortBy: SortBy(column: "updated_at", order: .descending))
/// ```
public struct SortBy: Encodable, Sendable {
  /// The column to sort by, e.g. `"name"`, `"created_at"`, `"updated_at"`.
  public var column: String?

  /// The sort direction.
  public var order: SortOrder?

  public init(column: String? = nil, order: SortOrder? = nil) {
    self.column = column
    self.order = order
  }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
swift test --filter StorageTests
```

Expected: all tests pass (no other files reference the old `String?` order)

- [ ] **Step 5: Commit**

```bash
git add Sources/Storage/Types.swift Tests/StorageTests/ValueTypesTests.swift
git commit -m "refactor(storage): update SortBy.order to use SortOrder"
```

---

## Task 6: Update BucketOptions and BucketParameters encoding

**Files:**
- Modify: `Sources/Storage/Types.swift`
- Modify: `Sources/Storage/StorageClient.swift`
- Modify: `Tests/StorageTests/BucketOptionsTests.swift`

- [ ] **Step 1: Update BucketOptionsTests**

Replace the full content of `Tests/StorageTests/BucketOptionsTests.swift`:

```swift
import XCTest
@testable import Storage

final class BucketOptionsTests: XCTestCase {
  func testDefaultInitialization() {
    let options = BucketOptions()

    XCTAssertFalse(options.isPublic)
    XCTAssertNil(options.fileSizeLimit)
    XCTAssertNil(options.allowedMimeTypes)
  }

  func testCustomInitialization() {
    let options = BucketOptions(
      isPublic: true,
      fileSizeLimit: .megabytes(5),
      allowedMimeTypes: ["image/jpeg", "image/png"]
    )

    XCTAssertTrue(options.isPublic)
    XCTAssertEqual(options.fileSizeLimit, .megabytes(5))
    XCTAssertEqual(options.fileSizeLimit?.bytes, 5_242_880)
    XCTAssertEqual(options.allowedMimeTypes, ["image/jpeg", "image/png"])
  }

  func testIntegerLiteralFileSizeLimit() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: 5_242_880)
    XCTAssertEqual(options.fileSizeLimit?.bytes, 5_242_880)
  }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
swift test --filter BucketOptionsTests 2>&1 | head -20
```

Expected: `error: value of type 'BucketOptions' has no member 'isPublic'`

- [ ] **Step 3: Update BucketOptions in Types.swift**

Replace the `BucketOptions` struct:

```swift
/// Options used when creating or updating a Storage bucket.
///
/// Pass an instance to ``StorageClient/createBucket(_:options:)`` or
/// ``StorageClient/updateBucket(_:options:)``.
///
/// ## Example
///
/// ```swift
/// // Create a public bucket that only accepts images up to 5 MB
/// try await storage.createBucket(
///   "avatars",
///   options: BucketOptions(
///     isPublic: true,
///     fileSizeLimit: .megabytes(5),
///     allowedMimeTypes: ["image/*"]
///   )
/// )
/// ```
public struct BucketOptions: Sendable {
  /// Whether the bucket is publicly accessible without an authorization token.
  ///
  /// Defaults to `false`.
  public var isPublic: Bool

  /// The maximum file size allowed for uploads.
  ///
  /// Use ``StorageByteCount`` factory methods for readable values:
  /// `.megabytes(5)`, `.gigabytes(1)`, or an integer literal for raw bytes.
  /// Pass `nil` to impose no per-bucket limit (the default).
  public var fileSizeLimit: StorageByteCount?

  /// MIME types accepted during upload to this bucket.
  ///
  /// Each entry can be an exact MIME type (`"image/png"`) or a wildcard (`"image/*"`).
  /// Pass `nil` to allow all MIME types (the default).
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
}
```

- [ ] **Step 4: Update BucketParameters in StorageClient.swift**

Replace the private `BucketParameters` struct in `Sources/Storage/StorageClient.swift`:

```swift
struct BucketParameters: Encodable {
  var id: String
  var name: String
  var isPublic: Bool
  var fileSizeLimit: Int64?
  var allowedMimeTypes: [String]?

  // Explicit CodingKeys required: keyEncodingStrategy (.convertToSnakeCase) does not
  // apply when CodingKeys are present, so all wire-format keys are listed explicitly.
  enum CodingKeys: String, CodingKey {
    case id
    case name
    case isPublic = "public"
    case fileSizeLimit = "file_size_limit"
    case allowedMimeTypes = "allowed_mime_types"
  }
}
```

- [ ] **Step 5: Update BucketParameters usage in createBucket and updateBucket**

In `StorageClient.swift`, `createBucket` and `updateBucket` both build a `BucketParameters`. Update both call sites to use `isPublic` and `fileSizeLimit?.bytes`:

```swift
// In createBucket(_:options:)
body: .data(
  encoder.encode(
    BucketParameters(
      id: id,
      name: id,
      isPublic: options.isPublic,
      fileSizeLimit: options.fileSizeLimit?.bytes,
      allowedMimeTypes: options.allowedMimeTypes
    )
  )
)

// In updateBucket(_:options:)
body: .data(
  encoder.encode(
    BucketParameters(
      id: id,
      name: id,
      isPublic: options.isPublic,
      fileSizeLimit: options.fileSizeLimit?.bytes,
      allowedMimeTypes: options.allowedMimeTypes
    )
  )
)
```

- [ ] **Step 6: Run tests — expect pass**

```bash
swift test --filter StorageTests
```

Expected: all tests pass. The `testCreateBucket` and `testUpdateBucket` snapshots encode `"public":true` — the `CodingKeys` mapping ensures the wire key is still `"public"` despite the Swift property being named `isPublic`.

- [ ] **Step 7: Commit**

```bash
git add Sources/Storage/Types.swift Sources/Storage/StorageClient.swift \
  Tests/StorageTests/BucketOptionsTests.swift
git commit -m "refactor(storage): rename BucketOptions.public to isPublic, fileSizeLimit to StorageByteCount"
```

---

## Task 7: Update FileOptions — remove duplex and headers

**Files:**
- Modify: `Sources/Storage/Types.swift`
- Modify: `Sources/Storage/StorageFileAPI.swift`
- Modify: `Tests/StorageTests/FileOptionsTests.swift`
- Modify: `Tests/StorageTests/StorageFileAPITests.swift`

- [ ] **Step 1: Update FileOptionsTests**

Replace the full content of `Tests/StorageTests/FileOptionsTests.swift`:

```swift
import XCTest
@testable import Storage

final class FileOptionsTests: XCTestCase {
  func testDefaultInitialization() {
    let options = FileOptions()

    XCTAssertEqual(options.cacheControl, "3600")
    XCTAssertNil(options.contentType)
    XCTAssertFalse(options.upsert)
    XCTAssertNil(options.metadata)
  }

  func testCustomInitialization() {
    let metadata: [String: AnyJSON] = ["key": .string("value")]
    let options = FileOptions(
      cacheControl: "7200",
      contentType: "image/jpeg",
      upsert: true,
      metadata: metadata
    )

    XCTAssertEqual(options.cacheControl, "7200")
    XCTAssertEqual(options.contentType, "image/jpeg")
    XCTAssertTrue(options.upsert)
    XCTAssertEqual(options.metadata?["key"], .string("value"))
  }
}
```

- [ ] **Step 2: Update the testUploadToSignedURL_fromFileURL snapshot test**

In `Tests/StorageTests/StorageFileAPITests.swift`, `testUploadToSignedURL_fromFileURL` passes `FileOptions(headers: ["X-Mode": "test"])`. Remove the custom headers option and update the snapshot to remove the `X-Mode` header line:

```swift
func testUploadToSignedURL_fromFileURL() async throws {
  Mock(
    url: url.appendingPathComponent("object/upload/sign/bucket/file.txt"),
    ignoreQuery: true,
    statusCode: 200,
    data: [
      .put: Data(
        """
        {
          "Key": "bucket/file.txt"
        }
        """.utf8)
    ]
  )
  .snapshotRequest {
    #"""
    curl \
    	--request PUT \
    	--header "Accept: application/json" \
    	--header "Cache-Control: max-age=3600" \
    	--header "Content-Length: 285" \
    	--header "Content-Type: multipart/form-data; boundary=alamofire.boundary.e56f43407f772505" \
    	--header "X-Client-Info: storage-swift/0.0.0" \
    	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
    	--header "x-upsert: false" \
    	--data "--alamofire.boundary.e56f43407f772505\#r
    Content-Disposition: form-data; name=\"cacheControl\"\#r
    \#r
    3600\#r
    --alamofire.boundary.e56f43407f772505\#r
    Content-Disposition: form-data; name=\"\"; filename=\"file.txt\"\#r
    Content-Type: text/plain\#r
    \#r
    hello world!
    \#r
    --alamofire.boundary.e56f43407f772505--\#r
    " \
    	"http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi"
    """#
  }
  .register()

  let response = try await storage.from("bucket")
    .uploadToSignedURL(
      "file.txt",
      token: "abc.def.ghi",
      fileURL: Bundle.module.url(forResource: "file", withExtension: "txt")!
    )

  XCTAssertEqual(response.path, "file.txt")
  XCTAssertEqual(response.fullPath, "bucket/file.txt")
}
```

> Note: The `Content-Length` in the snapshot may change slightly once `headers` is removed because the multipart body no longer injects extra headers. Run the test once after the implementation step — if InlineSnapshotTesting updates the snapshot automatically, accept the diff. If not, update `Content-Length: 285` to match the actual value.

- [ ] **Step 3: Run tests — expect compile failure**

```bash
swift test --filter StorageTests 2>&1 | head -20
```

Expected: `error: extra argument 'headers' in call` (from `FileOptions(headers:...)`)

- [ ] **Step 4: Update FileOptions in Types.swift**

Replace the `FileOptions` struct:

```swift
/// Options that control how a file is stored when uploading or updating it in a bucket.
///
/// ## Example
///
/// ```swift
/// let options = FileOptions(
///   cacheControl: "86400",         // cache for 24 hours
///   contentType: "image/jpeg",
///   upsert: true,
///   metadata: ["userId": "abc123"]
/// )
/// try await storage.from("avatars").upload("user.jpg", data: jpegData, options: options)
/// ```
public struct FileOptions: Sendable {
  /// The `Cache-Control` header value for the stored object.
  ///
  /// Accepts standard Cache-Control directives such as `"3600"`, `"no-cache"`,
  /// or `"public, max-age=3600"`. Defaults to `"3600"`.
  public var cacheControl: String

  /// The MIME type of the file, sent as the `Content-Type` header.
  ///
  /// When `nil`, the MIME type is inferred from the file extension.
  public var contentType: String?

  /// Whether to overwrite an existing file at the same path.
  ///
  /// When `true`, any existing object at the path is silently replaced.
  /// Defaults to `false`.
  public var upsert: Bool

  /// Arbitrary key-value metadata attached to the object in the storage backend.
  ///
  /// Values must be JSON-serialisable. Defaults to `nil`.
  public var metadata: [String: AnyJSON]?

  public init(
    cacheControl: String = "3600",
    contentType: String? = nil,
    upsert: Bool = false,
    metadata: [String: AnyJSON]? = nil
  ) {
    self.cacheControl = cacheControl
    self.contentType = contentType
    self.upsert = upsert
    self.metadata = metadata
  }
}
```

- [ ] **Step 5: Update multipartHeaders in StorageFileAPI.swift**

Replace the `multipartHeaders` private method:

```swift
private func multipartHeaders(options: FileOptions) -> [String: String] {
  var headers: [String: String] = [:]
  headers.setIfMissing(Header.cacheControl, value: "max-age=\(options.cacheControl)")
  return headers
}
```

Also remove the `duplex` case from `Header` enum:

```swift
private enum Header {
  static let cacheControl = "Cache-Control"
  static let contentType = "Content-Type"
  static let xUpsert = "x-upsert"
}
```

- [ ] **Step 6: Run tests — verify pass (update snapshots if needed)**

```bash
swift test --filter StorageTests
```

If `testUploadToSignedURL_fromFileURL` fails with a snapshot mismatch on `Content-Length`, run with record mode or accept the updated snapshot.

- [ ] **Step 7: Commit**

```bash
git add Sources/Storage/Types.swift Sources/Storage/StorageFileAPI.swift \
  Tests/StorageTests/FileOptionsTests.swift Tests/StorageTests/StorageFileAPITests.swift
git commit -m "refactor(storage): remove duplex and headers from FileOptions"
```

---

## Task 8: Make SearchOptions.prefix internal

**Files:**
- Modify: `Sources/Storage/Types.swift`

- [ ] **Step 1: Change prefix access level in Types.swift**

In `Sources/Storage/Types.swift`, locate `SearchOptions` and change `prefix` from `var` (implicitly `public` since the struct is `public`) to an explicitly `internal` property. Also remove it from the public `init`:

```swift
public struct SearchOptions: Encodable, Sendable {
  var prefix: String  // internal — set by list() before encoding, never by callers

  /// The maximum number of files to return. Defaults to `100` when `nil`.
  public var limit: Int?

  /// The zero-based index of the first file to return.
  public var offset: Int?

  /// The column and direction used to sort the results.
  public var sortBy: SortBy?

  /// A string used to filter files whose names contain the given value.
  public var search: String?

  public init(
    limit: Int? = nil,
    offset: Int? = nil,
    sortBy: SortBy? = nil,
    search: String? = nil
  ) {
    prefix = ""
    self.limit = limit
    self.offset = offset
    self.sortBy = sortBy
    self.search = search
  }
}
```

- [ ] **Step 2: Run tests — expect pass**

```bash
swift test --filter StorageTests
```

Expected: all tests pass (no test ever set `prefix` directly)

- [ ] **Step 3: Commit**

```bash
git add Sources/Storage/Types.swift
git commit -m "refactor(storage): make SearchOptions.prefix internal"
```

---

## Task 9: Remove SignedURL, rename FileObjectV2 → FileInfo

**Files:**
- Modify: `Sources/Storage/Types.swift`
- Modify: `Sources/Storage/StorageFileAPI.swift`

- [ ] **Step 1: Remove SignedURL and rename FileObjectV2 in Types.swift**

In `Sources/Storage/Types.swift`:

1. Delete the entire `SignedURL` struct (the one with `error: String?`, `signedURL: URL`, `path: String`).
2. Rename `FileObjectV2` → `FileInfo` and update the doc comment:

```swift
/// Detailed metadata for a file stored in a Supabase Storage bucket.
///
/// Returned by ``StorageFileAPI/info(path:)``. Includes content-level details
/// such as file size, ETag, and content type that are not available in the
/// directory-listing type ``FileObject``.
public struct FileInfo: Identifiable, Hashable, Decodable, Sendable {
  /// The unique storage identifier for the object.
  public let id: String

  /// The internal version string of the object, used for cache busting.
  public let version: String

  /// The name of the file, e.g. `"avatar.png"`.
  public let name: String

  /// The identifier of the bucket that contains this object.
  public let bucketId: String?

  /// When the object was last modified.
  public let updatedAt: Date?

  /// When the object was first created.
  public let createdAt: Date?

  /// When the object was last accessed.
  public let lastAccessedAt: Date?

  /// The file size in bytes.
  public let size: Int?

  /// The `Cache-Control` header value associated with the object.
  public let cacheControl: String?

  /// The MIME content type of the object (e.g. `"image/png"`).
  public let contentType: String?

  /// The ETag of the object, for conditional HTTP requests.
  public let etag: String?

  /// The `Last-Modified` date as reported by the storage server.
  public let lastModified: Date?

  /// Arbitrary key-value metadata attached to the object at upload time.
  public let metadata: [String: AnyJSON]?

  enum CodingKeys: String, CodingKey {
    case id
    case version
    case name
    case bucketId = "bucket_id"
    case updatedAt = "updated_at"
    case createdAt = "created_at"
    case lastAccessedAt = "last_accessed_at"
    case size
    case cacheControl = "cache_control"
    case contentType = "content_type"
    case etag
    case lastModified = "last_modified"
    case metadata
  }
}
```

- [ ] **Step 2: Update info() return type in StorageFileAPI.swift**

Find `func info(path: String) async throws -> FileObjectV2` and change to:

```swift
public func info(path: String) async throws -> FileInfo {
  let _path = _getFinalPath(path)
  return try await client.fetchDecoded(.get, "object/info/\(_path)")
}
```

- [ ] **Step 3: Update StorageFileAPITests.testInfo**

In `Tests/StorageTests/StorageFileAPITests.swift`, the test already stores the result as `let info = ...` and just calls `.name`. No type annotation needed — it compiles with both the old and new name. Verify there is no explicit `FileObjectV2` type annotation to update.

- [ ] **Step 4: Run tests — expect pass**

```bash
swift test --filter StorageTests
```

Expected: all tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/Storage/Types.swift Sources/Storage/StorageFileAPI.swift
git commit -m "refactor(storage): rename FileObjectV2 to FileInfo, remove legacy SignedURL type"
```

---

## Task 10: Update createSignedURL and createSignedURLs

Changes: `expiresIn: Int` → `Duration`, `download: String?`/`Bool` overloads → `download: DownloadBehavior? = nil`.

**Files:**
- Modify: `Sources/Storage/StorageFileAPI.swift`
- Modify: `Tests/StorageTests/StorageFileAPITests.swift`
- Modify: `Tests/StorageTests/SupabaseStorageTests.swift`

- [ ] **Step 1: Update StorageFileAPITests — createSignedURL call sites**

In `Tests/StorageTests/StorageFileAPITests.swift`, update every `createSignedURL` and `createSignedURLs` call:

```swift
// testCreateSignedURL — change expiresIn: 3600 → .seconds(3600)
let url = try await storage.from("bucket").createSignedURL(
  path: "file.txt",
  expiresIn: .seconds(3600)
)

// testCreateSignedURL_download — change download: true → download: .download
let url = try await storage.from("bucket").createSignedURL(
  path: "file.txt",
  expiresIn: .seconds(3600),
  download: .download
)

// testCreateSignedURLs — change expiresIn: 3600 → .seconds(3600)
let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
  paths: paths,
  expiresIn: .seconds(3600)
)

// testCreateSignedURLs_download — change download: true → download: .download
let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
  paths: paths,
  expiresIn: .seconds(3600),
  download: .download
)

// testCreateSignedURLs_withNullSignedURL — change expiresIn: 3600 → .seconds(3600)
let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
  paths: ["file.txt", "missing.txt"],
  expiresIn: .seconds(3600)
)

// testCreateSignedURL_cacheNonce — change expiresIn: 3600 → .seconds(3600)
let url = try await storage.from("bucket").createSignedURL(
  path: "file.txt",
  expiresIn: .seconds(3600),
  cacheNonce: "abc123"
)

// testCreateSignedURLs_cacheNonce — change expiresIn: 3600 → .seconds(3600)
let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
  paths: ["file.txt"],
  expiresIn: .seconds(3600),
  cacheNonce: "abc123"
)
```

- [ ] **Step 2: Update SupabaseStorageTests.testCreateSignedURLs**

In `Tests/StorageTests/SupabaseStorageTests.swift`:

```swift
let results: [SignedURLResult] = try await sut.from(bucketId).createSignedURLs(
  paths: ["file1.txt", "file2.txt"],
  expiresIn: .seconds(60)
)
```

- [ ] **Step 3: Run tests — expect compile failure**

```bash
swift test --filter StorageTests 2>&1 | head -20
```

Expected: `error: cannot convert value of type 'Duration' to expected argument type 'Int'`

- [ ] **Step 4: Update makeSignedURL in StorageFileAPI.swift**

Replace the `makeSignedURL` private method:

```swift
private func makeSignedURL(
  _ signedURL: String,
  download: DownloadBehavior?,
  cacheNonce: String? = nil
) throws -> URL {
  guard let signedURLComponents = URLComponents(string: signedURL),
    var baseComponents = URLComponents(url: client.url, resolvingAgainstBaseURL: false)
  else {
    throw URLError(.badURL)
  }

  baseComponents.path +=
    signedURLComponents.path.hasPrefix("/")
    ? signedURLComponents.path : "/\(signedURLComponents.path)"
  baseComponents.queryItems = signedURLComponents.queryItems

  if let download {
    baseComponents.queryItems = baseComponents.queryItems ?? []
    let value: String
    switch download {
    case .download:              value = ""
    case .downloadAs(let name):  value = name
    }
    baseComponents.queryItems!.append(URLQueryItem(name: "download", value: value))
  }

  if let cacheNonce {
    baseComponents.queryItems = baseComponents.queryItems ?? []
    baseComponents.queryItems!.append(URLQueryItem(name: "cacheNonce", value: cacheNonce))
  }

  guard let url = baseComponents.url else {
    throw URLError(.badURL)
  }
  return url
}
```

- [ ] **Step 5: Update createSignedURL in StorageFileAPI.swift**

Replace both `createSignedURL` overloads with a single method:

```swift
/// Creates a signed URL that grants time-limited access to a private file.
///
/// - Parameters:
///   - path: The file path within the bucket, e.g. `"folder/image.png"`.
///   - expiresIn: How long until the signed URL expires, e.g. `.seconds(3600)`.
///   - download: When non-`nil`, the browser treats the URL as a file download.
///   - transform: Optional on-the-fly image transformation applied before the file is served.
///   - cacheNonce: An opaque string appended as a `cacheNonce` query parameter.
/// - Returns: A signed `URL` ready to be shared or embedded.
/// - Throws: ``StorageError`` if the file does not exist or the request fails.
public func createSignedURL(
  path: String,
  expiresIn: Duration,
  download: DownloadBehavior? = nil,
  transform: TransformOptions? = nil,
  cacheNonce: String? = nil
) async throws -> URL {
  struct Body: Encodable {
    let expiresIn: Int
    let transform: TransformOptions?
  }

  let encoder = JSONEncoder.unconfiguredEncoder
  let response: SignedURLAPIResponse = try await client.fetchDecoded(
    .post,
    "object/sign/\(bucketId)/\(path)",
    body: .data(
      encoder.encode(
        Body(expiresIn: Int(expiresIn.components.seconds), transform: transform)
      )
    )
  )

  return try makeSignedURL(response.signedURL, download: download, cacheNonce: cacheNonce)
}
```

- [ ] **Step 6: Update createSignedURLs in StorageFileAPI.swift**

Replace both `createSignedURLs` overloads with a single method:

```swift
/// Creates signed URLs for multiple files in a single request.
///
/// - Parameters:
///   - paths: The file paths within the bucket.
///   - expiresIn: How long until the signed URLs expire.
///   - download: When non-`nil`, the browser treats each URL as a file download.
///   - cacheNonce: An opaque string appended as a `cacheNonce` query parameter.
/// - Returns: An array of ``SignedURLResult`` values, one per input path.
/// - Throws: ``StorageError`` if the batch request itself fails.
public func createSignedURLs(
  paths: [String],
  expiresIn: Duration,
  download: DownloadBehavior? = nil,
  cacheNonce: String? = nil
) async throws -> [SignedURLResult] {
  struct Params: Encodable {
    let expiresIn: Int
    let paths: [String]
  }

  let encoder = JSONEncoder.unconfiguredEncoder
  let response: [SignedURLsAPIResponse] = try await client.fetchDecoded(
    .post,
    "object/sign/\(bucketId)",
    body: .data(encoder.encode(Params(expiresIn: Int(expiresIn.components.seconds), paths: paths)))
  )

  return try response.map { item in
    if let signedURLString = item.signedURL {
      let url = try makeSignedURL(signedURLString, download: download, cacheNonce: cacheNonce)
      return .success(path: item.path, signedURL: url)
    } else {
      return .failure(path: item.path, error: item.error ?? "Unknown error")
    }
  }
}
```

- [ ] **Step 7: Run tests — expect pass**

```bash
swift test --filter StorageTests
```

Expected: all tests pass

- [ ] **Step 8: Commit**

```bash
git add Sources/Storage/StorageFileAPI.swift \
  Tests/StorageTests/StorageFileAPITests.swift \
  Tests/StorageTests/SupabaseStorageTests.swift
git commit -m "refactor(storage): update createSignedURL/createSignedURLs to use Duration and DownloadBehavior"
```

---

## Task 11: Update getPublicURL

**Files:**
- Modify: `Sources/Storage/StorageFileAPI.swift`
- Modify: `Tests/StorageTests/SupabaseStorageTests.swift`

- [ ] **Step 1: Update SupabaseStorageTests.testGetPublicURL**

In `Tests/StorageTests/SupabaseStorageTests.swift`, update the `testGetPublicURL` test:

```swift
func testGetPublicURL() throws {
  let sut = makeSUT()
  let path = "README.md"

  let baseUrl = try sut.from(bucketId).getPublicURL(path: path)
  XCTAssertEqual(baseUrl.absoluteString, "\(Self.supabaseURL)/object/public/\(bucketId)/\(path)")

  let baseUrlWithDownload = try sut.from(bucketId).getPublicURL(
    path: path,
    download: .download
  )
  assertInlineSnapshot(of: baseUrlWithDownload, as: .description) {
    """
    http://localhost:54321/storage/v1/object/public/tests/README.md?download=
    """
  }

  let baseUrlWithDownloadAndFileName = try sut.from(bucketId).getPublicURL(
    path: path, download: .downloadAs("test")
  )
  assertInlineSnapshot(of: baseUrlWithDownloadAndFileName, as: .description) {
    """
    http://localhost:54321/storage/v1/object/public/tests/README.md?download=test
    """
  }

  let baseUrlWithAllOptions = try sut.from(bucketId).getPublicURL(
    path: path, download: .downloadAs("test"),
    options: TransformOptions(width: 300, height: 300)
  )
  assertInlineSnapshot(of: baseUrlWithAllOptions, as: .description) {
    """
    http://localhost:54321/storage/v1/render/image/public/tests/README.md?download=test&width=300&height=300
    """
  }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
swift test --filter SupabaseStorageTests 2>&1 | head -20
```

Expected: `error: cannot convert value of type 'DownloadBehavior' to expected argument type 'String?'`

- [ ] **Step 3: Replace both getPublicURL overloads in StorageFileAPI.swift**

```swift
/// Returns the public URL for a file in a public bucket.
///
/// The URL is constructed locally without a network request.
///
/// - Parameters:
///   - path: The path of the file within the bucket.
///   - download: When non-`nil`, the browser treats the URL as a file download.
///   - options: Optional on-the-fly image transformation.
///   - cacheNonce: An opaque string appended as a `cacheNonce` query parameter.
/// - Returns: The public `URL` for the file.
/// - Throws: `URLError(.badURL)` if the resulting URL cannot be constructed.
public func getPublicURL(
  path: String,
  download: DownloadBehavior? = nil,
  options: TransformOptions? = nil,
  cacheNonce: String? = nil
) throws -> URL {
  var queryItems: [URLQueryItem] = []

  guard
    var components = URLComponents(url: client.url, resolvingAgainstBaseURL: true)
  else {
    throw URLError(.badURL)
  }

  if let download {
    let value: String
    switch download {
    case .download:              value = ""
    case .downloadAs(let name):  value = name
    }
    queryItems.append(URLQueryItem(name: "download", value: value))
  }

  if let optionsQueryItems = options?.queryItems {
    queryItems.append(contentsOf: optionsQueryItems)
  }

  if let cacheNonce {
    queryItems.append(URLQueryItem(name: "cacheNonce", value: cacheNonce))
  }

  let renderPath = options.map { !$0.isEmpty } == true ? "render/image" : "object"
  components.path += "/\(renderPath)/public/\(bucketId)/\(path)"
  components.queryItems = !queryItems.isEmpty ? queryItems : nil

  guard let generatedUrl = components.url else {
    throw URLError(.badURL)
  }
  return generatedUrl
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
swift test --filter StorageTests
```

Expected: all tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/Storage/StorageFileAPI.swift Tests/StorageTests/SupabaseStorageTests.swift
git commit -m "refactor(storage): update getPublicURL to use DownloadBehavior"
```

---

## Task 12: Normalize uploadToSignedURL default options

**Files:**
- Modify: `Sources/Storage/StorageFileAPI.swift`

- [ ] **Step 1: Update the two public uploadToSignedURL signatures**

Change `options: FileOptions? = nil` → `options: FileOptions = FileOptions()` on both overloads.

Also update `_uploadToSignedURL` to receive `FileOptions` (non-optional) and remove the nil coalescing:

```swift
// Public data overload
@discardableResult
public func uploadToSignedURL(
  _ path: String,
  token: String,
  data: Data,
  options: FileOptions = FileOptions()
) async throws -> SignedURLUploadResponse {
  try await _uploadToSignedURL(path: path, token: token, file: .data(data), options: options)
}

// Public fileURL overload
@discardableResult
public func uploadToSignedURL(
  _ path: String,
  token: String,
  fileURL: URL,
  options: FileOptions = FileOptions()
) async throws -> SignedURLUploadResponse {
  try await _uploadToSignedURL(path: path, token: token, file: .url(fileURL), options: options)
}

// Private implementation — options now non-optional
private func _uploadToSignedURL(
  path: String,
  token: String,
  file: FileUpload,
  options: FileOptions
) async throws -> SignedURLUploadResponse {
  var headers = multipartHeaders(options: options)
  headers[Header.xUpsert] = "\(options.upsert)"

  let response: SignedUploadResponse = try await uploadMultipart(
    .put,
    url: storageURL(
      path: "object/upload/sign/\(bucketId)/\(path)",
      queryItems: [URLQueryItem(name: "token", value: token)]
    ),
    path: path,
    file: file,
    options: options,
    headers: headers
  )
  return SignedURLUploadResponse(path: path, fullPath: response.Key)
}
```

Also update `FileUpload.defaultOptions()` — it was used only by `_uploadToSignedURL`. Since we removed the nil-coalescing that called it, remove the method entirely from `FileUpload`.

- [ ] **Step 2: Run tests — expect pass**

```bash
swift test --filter StorageTests
```

Expected: all tests pass

- [ ] **Step 3: Commit**

```bash
git add Sources/Storage/StorageFileAPI.swift
git commit -m "refactor(storage): normalize uploadToSignedURL default options to FileOptions()"
```

---

## Task 13: Add UploadProgress type

**Files:**
- Modify: `Sources/Storage/Types.swift`
- Create: `Tests/StorageTests/UploadProgressTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/StorageTests/UploadProgressTests.swift`:

```swift
import XCTest
@testable import Storage

final class UploadProgressTests: XCTestCase {

  func testFractionCompleted_midUpload() {
    let progress = UploadProgress(totalBytesSent: 500, totalBytesExpectedToSend: 1000)
    XCTAssertEqual(progress.fractionCompleted, 0.5, accuracy: 0.001)
  }

  func testFractionCompleted_complete() {
    let progress = UploadProgress(totalBytesSent: 1000, totalBytesExpectedToSend: 1000)
    XCTAssertEqual(progress.fractionCompleted, 1.0, accuracy: 0.001)
  }

  func testFractionCompleted_zeroTotal() {
    let progress = UploadProgress(totalBytesSent: 0, totalBytesExpectedToSend: 0)
    XCTAssertEqual(progress.fractionCompleted, 0.0)
  }

  func testFractionCompleted_start() {
    let progress = UploadProgress(totalBytesSent: 0, totalBytesExpectedToSend: 2048)
    XCTAssertEqual(progress.fractionCompleted, 0.0)
  }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
swift test --filter UploadProgressTests 2>&1 | head -20
```

Expected: `error: cannot find type 'UploadProgress' in scope`

- [ ] **Step 3: Add UploadProgress to Types.swift**

Add after the `FileUploadResponse` declaration in `Sources/Storage/Types.swift`:

```swift
/// Reports upload progress for a file upload operation.
///
/// Passed to the `progress` closure on upload methods such as
/// ``StorageFileAPI/upload(_:data:options:progress:)``.
///
/// ## Example
///
/// ```swift
/// try await bucket.upload("video.mp4", fileURL: localURL) { progress in
///   print("\(Int(progress.fractionCompleted * 100))%")
/// }
/// ```
public struct UploadProgress: Sendable {
  /// The total number of bytes sent so far.
  public let totalBytesSent: Int64

  /// The total number of bytes expected to be sent.
  public let totalBytesExpectedToSend: Int64

  /// Upload completion fraction, from `0.0` to `1.0`.
  ///
  /// Returns `0.0` when `totalBytesExpectedToSend` is zero.
  public var fractionCompleted: Double {
    guard totalBytesExpectedToSend > 0 else { return 0 }
    return Double(totalBytesSent) / Double(totalBytesExpectedToSend)
  }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
swift test --filter UploadProgressTests
```

Expected: `Test Suite 'UploadProgressTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/Storage/Types.swift Tests/StorageTests/UploadProgressTests.swift
git commit -m "feat(storage): add UploadProgress type"
```

---

## Task 14: Add UploadProgressDelegate and progress to upload/update

**Files:**
- Modify: `Sources/Storage/StorageFileAPI.swift`
- Modify: `Tests/StorageTests/StorageFileAPITests.swift`

- [ ] **Step 1: Add UploadProgressDelegate to StorageFileAPI.swift**

Add this private class at the bottom of `Sources/Storage/StorageFileAPI.swift` (before the final `}`):

```swift
// MARK: - Upload progress

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let onProgress: @Sendable (UploadProgress) -> Void

  init(onProgress: @escaping @Sendable (UploadProgress) -> Void) {
    self.onProgress = onProgress
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    onProgress(
      UploadProgress(
        totalBytesSent: totalBytesSent,
        totalBytesExpectedToSend: totalBytesExpectedToSend
      )
    )
  }
}
```

- [ ] **Step 2: Update uploadMultipart to accept a progress closure**

Change the `uploadMultipart` private method signature and body:

```swift
private func uploadMultipart<Response: Decodable>(
  _ method: HTTPMethod,
  url: URL,
  path: String,
  file: FileUpload,
  options: FileOptions,
  headers: [String: String],
  progress: (@Sendable (UploadProgress) -> Void)?
) async throws -> Response {
  #if DEBUG
    let builder = MultipartBuilder(
      boundary: testingBoundary.value ?? "----sb-\(UUID().uuidString)")
  #else
    let builder = MultipartBuilder()
  #endif

  let multipart = file.append(to: builder, withPath: path, options: options)

  var headers = headers
  headers[Header.contentType] = multipart.contentType

  let request = try await client.http.createRequest(
    method,
    url: url,
    headers: client.mergedHeaders(headers)
  )

  do {
    client.logRequest(method, url: url)
    let data: Data
    let response: URLResponse
    let delegate = progress.map { UploadProgressDelegate(onProgress: $0) }

    if try file.usesTempFileUpload {
      let tempFile = try multipart.buildToTempFile()
      defer { try? FileManager.default.removeItem(at: tempFile) }

      (data, response) = try await client.http.session.upload(
        for: request,
        fromFile: tempFile,
        delegate: delegate
      )
    } else {
      (data, response) = try await client.http.session.upload(
        for: request,
        from: try multipart.buildInMemory(),
        delegate: delegate
      )
    }

    let httpResponse = try client.http.validateResponse(response, data: data)
    client.logResponse(httpResponse, data: data)
    return try client.decoder.decode(Response.self, from: data)
  } catch {
    client.logFailure(error)
    throw translateStorageError(error)
  }
}
```

- [ ] **Step 3: Update _uploadOrUpdate to thread progress through**

```swift
private func _uploadOrUpdate(
  method: HTTPMethod,
  path: String,
  file: FileUpload,
  options: FileOptions?,
  progress: (@Sendable (UploadProgress) -> Void)? = nil
) async throws -> FileUploadResponse {
  let options = options ?? defaultFileOptions
  let cleanPath = _removeEmptyFolders(path)
  let _path = _getFinalPath(cleanPath)

  var headers = multipartHeaders(options: options)
  if method == .post {
    headers[Header.xUpsert] = "\(options.upsert)"
  }

  let response: UploadResponse = try await uploadMultipart(
    method,
    url: client.url.appendingPathComponent("object/\(_path)"),
    path: path,
    file: file,
    options: options,
    headers: headers,
    progress: progress
  )

  return FileUploadResponse(id: response.Id, path: path, fullPath: response.Key)
}
```

- [ ] **Step 4: Add progress parameter to all four public upload/update methods**

```swift
@discardableResult
public func upload(
  _ path: String,
  data: Data,
  options: FileOptions = FileOptions(),
  progress: (@Sendable (UploadProgress) -> Void)? = nil
) async throws -> FileUploadResponse {
  try await _uploadOrUpdate(method: .post, path: path, file: .data(data), options: options, progress: progress)
}

@discardableResult
public func upload(
  _ path: String,
  fileURL: URL,
  options: FileOptions = FileOptions(),
  progress: (@Sendable (UploadProgress) -> Void)? = nil
) async throws -> FileUploadResponse {
  try await _uploadOrUpdate(method: .post, path: path, file: .url(fileURL), options: options, progress: progress)
}

@discardableResult
public func update(
  _ path: String,
  data: Data,
  options: FileOptions = FileOptions(),
  progress: (@Sendable (UploadProgress) -> Void)? = nil
) async throws -> FileUploadResponse {
  try await _uploadOrUpdate(method: .put, path: path, file: .data(data), options: options, progress: progress)
}

@discardableResult
public func update(
  _ path: String,
  fileURL: URL,
  options: FileOptions = FileOptions(),
  progress: (@Sendable (UploadProgress) -> Void)? = nil
) async throws -> FileUploadResponse {
  try await _uploadOrUpdate(method: .put, path: path, file: .url(fileURL), options: options, progress: progress)
}
```

- [ ] **Step 5: Add a progress test to StorageFileAPITests**

Add this test to `Tests/StorageTests/StorageFileAPITests.swift`:

```swift
func testUploadWithProgressClosure() async throws {
  Mock(
    url: url.appendingPathComponent("object/bucket/file.txt"),
    statusCode: 200,
    data: [
      .post: Data(
        """
        {
          "Id": "123",
          "Key": "bucket/file.txt"
        }
        """.utf8
      )
    ]
  )
  .register()

  // Verify the upload still succeeds when a progress handler is provided.
  // Delegate-based progress callbacks require URLSession to actually transfer data,
  // so this test confirms wiring without asserting specific progress values.
  let response = try await storage.from("bucket").upload(
    "file.txt",
    data: Data("hello world".utf8),
    progress: { _ in }
  )

  XCTAssertEqual(response.id, "123")
  XCTAssertEqual(response.path, "file.txt")
  XCTAssertEqual(response.fullPath, "bucket/file.txt")
}
```

- [ ] **Step 6: Run tests — expect pass**

```bash
swift test --filter StorageTests
```

Expected: all tests pass

- [ ] **Step 7: Commit**

```bash
git add Sources/Storage/StorageFileAPI.swift Tests/StorageTests/StorageFileAPITests.swift
git commit -m "feat(storage): add upload progress reporting via optional trailing closure"
```

---

## Task 15: Add progress to uploadToSignedURL

**Files:**
- Modify: `Sources/Storage/StorageFileAPI.swift`

- [ ] **Step 1: Add progress to _uploadToSignedURL and both public overloads**

```swift
@discardableResult
public func uploadToSignedURL(
  _ path: String,
  token: String,
  data: Data,
  options: FileOptions = FileOptions(),
  progress: (@Sendable (UploadProgress) -> Void)? = nil
) async throws -> SignedURLUploadResponse {
  try await _uploadToSignedURL(path: path, token: token, file: .data(data), options: options, progress: progress)
}

@discardableResult
public func uploadToSignedURL(
  _ path: String,
  token: String,
  fileURL: URL,
  options: FileOptions = FileOptions(),
  progress: (@Sendable (UploadProgress) -> Void)? = nil
) async throws -> SignedURLUploadResponse {
  try await _uploadToSignedURL(path: path, token: token, file: .url(fileURL), options: options, progress: progress)
}

private func _uploadToSignedURL(
  path: String,
  token: String,
  file: FileUpload,
  options: FileOptions,
  progress: (@Sendable (UploadProgress) -> Void)? = nil
) async throws -> SignedURLUploadResponse {
  var headers = multipartHeaders(options: options)
  headers[Header.xUpsert] = "\(options.upsert)"

  let response: SignedUploadResponse = try await uploadMultipart(
    .put,
    url: storageURL(
      path: "object/upload/sign/\(bucketId)/\(path)",
      queryItems: [URLQueryItem(name: "token", value: token)]
    ),
    path: path,
    file: file,
    options: options,
    headers: headers,
    progress: progress
  )
  return SignedURLUploadResponse(path: path, fullPath: response.Key)
}
```

- [ ] **Step 2: Run all tests — expect full green**

```bash
swift test --filter StorageTests
```

Expected: all tests pass

- [ ] **Step 3: Run full suite**

```bash
swift test
```

Expected: all tests pass across all modules

- [ ] **Step 4: Commit**

```bash
git add Sources/Storage/StorageFileAPI.swift
git commit -m "feat(storage): add progress reporting to uploadToSignedURL"
```

---

## Done

All 15 tasks implement the full spec. The Storage module now has:

- Typed `ResizeMode`, `ImageFormat`, `SortOrder` (RawRepresentable, open to custom values)
- `StorageByteCount` with `.kilobytes()`, `.megabytes()`, `.gigabytes()` factory methods
- `DownloadBehavior` enum replacing six `download: String?`/`Bool` overloads with three single methods
- `BucketOptions.isPublic` (was `public`), `fileSizeLimit: StorageByteCount?` (was `String?`)
- `FileOptions` without HTTP-layer `duplex` and `headers`
- `createSignedURL`/`createSignedURLs` using `Duration` for `expiresIn`
- `FileInfo` (renamed from `FileObjectV2`), `SignedURL` removed
- Upload progress via optional `(@Sendable (UploadProgress) -> Void)?` trailing closure on all six upload-family methods
