# Storage v2: Typed Value Types + API Ergonomics

**Date:** 2026-07-02  
**Branch:** feature branch off `main`  
**PR target:** `main`  
**Source:** Backport from `release/v3` (`feat(storage)!: storage v3 #987`)  
**Goal:** Zero breaking changes — all existing v2 code compiles unchanged.

---

## Scope

Backport typed value types and API ergonomics improvements from v3 into v2 without breaking the existing public API. This is PR 1 of a 3-PR series:

- **PR 1 (this):** New value types + API ergonomics
- **PR 2:** `StorageTransferTask` + TUS resumable uploads (deferred)
- **PR 3:** Additional features (deferred)

---

## Files Changed

| File | Action |
|---|---|
| `Sources/Storage/Types.swift` | Add 7 new types; evolve `TransformOptions` and `SortBy` field types; absorb content from `BucketOptions.swift` and `TransformOptions.swift` |
| `Sources/Storage/BucketOptions.swift` | **Delete** (consolidated into `Types.swift`) |
| `Sources/Storage/TransformOptions.swift` | **Delete** (consolidated into `Types.swift`) |
| `Sources/Storage/StorageError.swift` | Add `StorageErrorCode` type + `StorageError` extension |
| `Sources/Storage/StorageBucketApi.swift` | Update `BucketParameters` for renamed field and `Int64` file size |
| `Sources/Storage/StorageFileApi.swift` | Add `DownloadBehavior` overloads; deprecate `Bool` download overloads |
| `Tests/StorageTests/` | Add/update tests for all new and changed types |

---

## New Types

All added to `Sources/Storage/Types.swift` unless noted.

### `StorageByteCount`

Value type for file size limits. Used in `BucketOptions.fileSizeLimit`.

```swift
public struct StorageByteCount: Sendable, Hashable {
    public let bytes: Int64
    public static func bytes(_ value: Int64) -> Self
    public static func kilobytes(_ value: Int64) -> Self
    public static func megabytes(_ value: Int64) -> Self
    public static func gigabytes(_ value: Int64) -> Self
}
extension StorageByteCount: ExpressibleByIntegerLiteral  // 10_485_760 → StorageByteCount
```

### `ResizeMode`

Open-ended struct (not enum) so custom backend values don't require SDK updates. `ExpressibleByStringLiteral` preserves backward compatibility when changing `TransformOptions.resize`.

```swift
public struct ResizeMode: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public static let cover   = ResizeMode("cover")
    public static let contain = ResizeMode("contain")
    public static let fill    = ResizeMode("fill")
}
```

### `ImageFormat`

Same open-ended struct pattern as `ResizeMode`.

```swift
public struct ImageFormat: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public static let origin = ImageFormat("origin")
    public static let webp   = ImageFormat("webp")
    public static let avif   = ImageFormat("avif")
}
```

### `SortOrder`

Same open-ended struct pattern.

```swift
public struct SortOrder: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public static let ascending  = SortOrder("asc")
    public static let descending = SortOrder("desc")
}
```

### `DownloadBehavior`

Controls the `?download=` query parameter on signed/public URLs.

```swift
public enum DownloadBehavior: Sendable {
    case withOriginalName       // → ?download=
    case named(String)          // → ?download=<filename>
}
```

### `UploadMethod`

Added now so it exists when PR 2 wires it up. Not used by any public API in this PR.

```swift
public enum UploadMethod: Sendable {
    case auto       // ≤6 MB → multipart, >6 MB → resumable
    case multipart
    case resumable
}
```

### `StorageErrorCode` (in `StorageError.swift`)

Open-ended struct with known static constants. Not `Decodable` — derived from `StorageError.error` string at the call site.

```swift
public struct StorageErrorCode: RawRepresentable, Sendable, Hashable {
    public var rawValue: String
    public static let unknown            = StorageErrorCode("unknown")
    public static let invalidJWT         = StorageErrorCode("InvalidJWT")
    public static let unauthorized       = StorageErrorCode("Unauthorized")
    public static let objectNotFound     = StorageErrorCode("not_found")
    public static let bucketNotFound     = StorageErrorCode("Bucket not found")
    public static let objectAlreadyExists = StorageErrorCode("Duplicate")
    public static let bucketAlreadyExists = StorageErrorCode("Duplicate")
    public static let invalidBucketName  = StorageErrorCode("Invalid Input")
    public static let entityTooLarge     = StorageErrorCode("Payload too large")
    public static let invalidMimeType    = StorageErrorCode("invalid_mime_type")
}
```

---

## Evolved Existing Types

### `TransformOptions.resize` and `.format`

Field types change from `String?` to typed structs. Because both `ResizeMode` and `ImageFormat` are `ExpressibleByStringLiteral`, all existing string-literal call sites continue to compile unchanged:

```swift
// Before (still compiles after change)
TransformOptions(resize: "cover", format: "webp")

// New preferred usage
TransformOptions(resize: .cover, format: .webp)
```

Wire format (JSON encoding) is identical in both cases — both encode to the raw `String` value.

### `SortBy.order`

Field type changes from `String?` to `SortOrder?`. Same backward-compat guarantee via `ExpressibleByStringLiteral`:

```swift
// Before (still compiles)
SortBy(column: "name", order: "asc")

// New preferred usage
SortBy(column: "name", order: .ascending)
```

### `BucketOptions` rename + type change

**Property rename** — `public var `public`: Bool` → `public var isPublic: Bool`:
- New `init(isPublic:fileSizeLimit:allowedMimeTypes:)` is the primary init
- Deprecated computed property bridges the old `public` name:
  ```swift
  @available(*, deprecated, renamed: "isPublic")
  public var `public`: Bool { get { isPublic } set { isPublic = newValue } }
  ```
- Deprecated init bridges the old label:
  ```swift
  @available(*, deprecated, renamed: "init(isPublic:fileSizeLimit:allowedMimeTypes:)")
  public init(public isPublic: Bool = false, fileSizeLimit: String? = nil, allowedMimeTypes: [String]? = nil)
  ```

**`fileSizeLimit` type change** — `String?` → `StorageByteCount?`:
- The deprecated init accepts `String?` and converts: `Int64(string).map(StorageByteCount.init)`
- `StorageBucketApi.BucketParameters.fileSizeLimit` changes from `String?` to `Int64?`, passing `options.fileSizeLimit?.bytes`
- **Side-effect fix:** this corrects a pre-existing wire format bug where the SDK was sending `"10485760"` (a JSON string) instead of `10485760` (a JSON number) as the server expects

### `StorageError` typed errors

`StorageError` struct is **unchanged** (retains `Decodable`, `statusCode: String?`, `message`, `error: String?`). A new extension adds:

```swift
extension StorageError {
    // Maps self.error string → StorageErrorCode; falls back to .unknown
    public var errorCode: StorageErrorCode { ... }
    public var isNotFound: Bool { errorCode == .objectNotFound || errorCode == .bucketNotFound }
    public var isUnauthorized: Bool { errorCode == .unauthorized || errorCode == .invalidJWT }
    public var isEntityTooLarge: Bool { errorCode == .entityTooLarge }
}
```

No changes to error construction or throwing — `StorageApi.execute()` is unchanged.

### `DownloadBehavior` overloads

The existing `download: Bool` overloads on `createSignedURL`, `createSignedURLs`, and `getPublicURL` are deprecated. New overloads accepting `DownloadBehavior?` are added:

```swift
// Deprecated (kept for backward compat)
func createSignedURL(path: String, expiresIn: Int, download: Bool, ...) async throws -> URL

// New preferred overload
func createSignedURL(path: String, expiresIn: Int, download: DownloadBehavior? = nil, ...) async throws -> URL
```

`DownloadBehavior` maps to the existing `download: String?` parameter:
- `nil` → `nil`
- `.withOriginalName` → `""`
- `.named("report.pdf")` → `"report.pdf"`

The primary `download: String?` overloads remain as the internal implementation delegate.

---

## Backward Compatibility Guarantee

Every existing call site continues to compile without changes:

| Old call site | Status |
|---|---|
| `TransformOptions(resize: "cover")` | Compiles — `ResizeMode: ExpressibleByStringLiteral` |
| `TransformOptions(format: "webp")` | Compiles — `ImageFormat: ExpressibleByStringLiteral` |
| `SortBy(column: "name", order: "asc")` | Compiles — `SortOrder: ExpressibleByStringLiteral` |
| `BucketOptions(public: true)` | Compiles — deprecated init bridge |
| `options.public = true` | Compiles — deprecated computed property bridge |
| `BucketOptions(fileSizeLimit: "10485760")` | Compiles — deprecated init bridge converts string |
| `createSignedURL(..., download: true)` | Compiles — deprecated Bool overload kept |
| `getPublicURL(..., download: false)` | Compiles — deprecated Bool overload kept |

---

## Testing

- `Tests/StorageTests/ValueTypesTests.swift` — new file, tests for all 7 new types (construction, encoding, string literal compat, `ExpressibleByIntegerLiteral`)
- `Tests/StorageTests/StorageErrorTests.swift` — add tests for `errorCode` computed property, `isNotFound`, `isUnauthorized`, `isEntityTooLarge`
- `Tests/StorageTests/BucketOptionsTests.swift` — update for `isPublic` rename, `StorageByteCount` file size, deprecated bridge
- `Tests/StorageTests/TransformOptionsTests.swift` — update for typed `resize`/`format` fields
- `Tests/StorageTests/FileOptionsTests.swift` — update if affected by consolidation

---

## Out of Scope (Deferred to Later PRs)

- `StorageTransferTask`, upload progress tracking, pause/resume/cancel
- TUS resumable uploads (`UploadMethod` wiring)
- `StorageError` structural overhaul (`statusCode: String?` → `Int?`, remove `Decodable`)
- Type renames: `StorageApi`/`StorageBucketApi` → `StorageClient`, `StorageFileApi` → `StorageFileAPI`
- `FileUploadResponse.id: String` → `UUID`
