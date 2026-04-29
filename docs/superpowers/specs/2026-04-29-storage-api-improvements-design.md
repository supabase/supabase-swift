# Storage Module API Improvements — Design Spec

**Date:** 2026-04-29
**Branch:** refactor/storage-http-client
**Breaking changes:** yes (target: next major version)

---

## Motivation

The Storage module has accumulated several rough edges since its initial implementation:

- Stringly-typed fields where closed/semi-closed value sets exist (`resize`, `format`, `order`)
- Type mismatches between request and response shapes (`fileSizeLimit: String?` vs `Bucket.fileSizeLimit: Int64?`)
- API surface that leaks HTTP-layer details into public option types (`duplex`, `headers` in `FileOptions`)
- Overload explosion from `download: String?` / `download: Bool` pairs across three methods (6 overloads total)
- A legacy `SignedURL` type with no current API usage
- `FileObjectV2` named after an internal API version, not a user concept
- No upload progress reporting

All changes are breaking. No backward-compatibility bridges are required.

---

## Section 1 — Type System: Typed Values

### Rationale

Backend-dependent string fields become `RawRepresentable` structs following the established `FunctionRegion` pattern. This gives users dot-syntax for known values while keeping the API open for new backend values without requiring an SDK update. `ExpressibleByStringLiteral` is added for ergonomic migration from raw strings.

`DownloadBehavior` is a local SDK abstraction (never sent as a raw string to the backend), so it stays a regular enum.

### New types

```swift
/// Resize mode for on-the-fly image transformation.
/// Follows the FunctionRegion pattern — open to custom backend values.
public struct ResizeMode: RawRepresentable, Hashable, Sendable, Encodable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Fill the target dimensions, cropping any overflow. Default.
    public static let cover   = ResizeMode(rawValue: "cover")
    /// Fit the image within the target dimensions, letterboxing if needed.
    public static let contain = ResizeMode(rawValue: "contain")
    /// Stretch the image to exactly fill the target dimensions.
    public static let fill    = ResizeMode(rawValue: "fill")
}

extension ResizeMode: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}

/// Output format for on-the-fly image transformation.
public struct ImageFormat: RawRepresentable, Hashable, Sendable, Encodable {
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

/// Sort direction for object list results.
public struct SortOrder: RawRepresentable, Hashable, Sendable, Encodable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let ascending  = SortOrder(rawValue: "asc")
    public static let descending = SortOrder(rawValue: "desc")
}

extension SortOrder: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}

/// Controls browser download behaviour for public and signed URLs.
/// Local SDK abstraction — not sent as a raw value to the backend.
public enum DownloadBehavior: Sendable {
    /// Trigger a browser download prompt using the file's original name.
    /// Wire format: appends `?download=` (empty string value) to the URL.
    case download
    /// Trigger a browser download prompt using a custom filename.
    /// Wire format: appends `?download=<filename>` to the URL.
    case downloadAs(String)
}
```

---

## Section 2 — Modified Option & Model Types

### `StorageByteCount` (new type)

A `Duration`-inspired value type for expressing byte counts in human-friendly units.
Uses `Int64` backing to avoid the precision loss of `Measurement<UnitInformationStorage>` (which uses `Double`)
and sidesteps the SI vs binary ambiguity of Foundation's `UnitInformationStorage`.
`ExpressibleByIntegerLiteral` allows raw byte values without wrapping.

```swift
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

Wire encoding: always sends `.bytes` as an `Int64` in the JSON body. The backend accepts integers
natively. `ExpressibleByStringLiteral` is deliberately omitted — the SDK owns unit conversion
rather than delegating it to the backend's string parser.

### `BucketOptions`

- Rename `public` → `isPublic` (matches `Bucket.isPublic`, avoids backtick escaping)
  - **Wire format:** the JSON key stays `"public"` — the internal `BucketParameters` encoding struct must explicitly map `isPublic` → `"public"` via `CodingKeys` or manual encoding
- `fileSizeLimit: String?` → `StorageByteCount?`
  - **Verified:** backend stores as integer; response `Bucket.fileSizeLimit` is already `Int64?`
  - The SDK sends `.bytes` as `Int64`; `ExpressibleByIntegerLiteral` preserves raw-byte call sites

```swift
// Before
BucketOptions(public: true, fileSizeLimit: "5242880")

// After — all equivalent
BucketOptions(isPublic: true, fileSizeLimit: .megabytes(5))
BucketOptions(isPublic: true, fileSizeLimit: .gigabytes(1))
BucketOptions(isPublic: true, fileSizeLimit: 5_242_880)   // ExpressibleByIntegerLiteral
```

### `FileOptions`

- `cacheControl: String` — **stays `String`**
  - Verified: backend accepts full Cache-Control header strings (e.g. `"no-cache"`, `"public, max-age=3600"`)
  - Changing to `Int` would lose expressiveness
- Remove `duplex: String?` — HTTP-layer detail, not a user concern
- Remove `headers: [String: String]?` — HTTP-layer detail; auth is handled by `TokenProvider`

```swift
public struct FileOptions: Sendable {
    public var cacheControl: String             // unchanged: "3600", "no-cache", etc.
    public var contentType: String?
    public var upsert: Bool
    public var metadata: [String: AnyJSON]?
    // removed: duplex, headers
}
```

### `TransformOptions`

- `resize: String?` → `ResizeMode?`
- `format: String?` → `ImageFormat?`

```swift
// Before
TransformOptions(resize: "cover", format: "webp")

// After
TransformOptions(resize: .cover, format: .webp)
```

### `SortBy`

- `order: String?` → `SortOrder?`

```swift
// Before
SortBy(column: "created_at", order: "desc")

// After
SortBy(column: "created_at", order: .descending)
```

### `SearchOptions`

- `prefix: String` becomes `internal`
  - It is a required field in the backend's list request body, but it is always populated
    from the `path` parameter passed to `list(path:options:)` — users never set it directly

### `StorageError`

- `statusCode: String?` — **stays `String?`**
  - Verified: backend error schema explicitly types it as `string` (e.g. `"404"`, `"429"`)
  - Changing to `Int?` would break JSON decoding

### `FileObjectV2` → `FileInfo`

Rename to `FileInfo`. The `V2` suffix reflects an internal API version, not a user-facing concept. Semantically: `FileObject` is a directory listing entry; `FileInfo` is detailed metadata for a specific file.

```swift
public struct FileInfo: Identifiable, Hashable, Decodable, Sendable {
    public let id: String
    public let version: String
    public let name: String
    public let bucketId: String?
    public let size: Int?
    public let contentType: String?
    public let etag: String?
    public let cacheControl: String?
    public let lastModified: Date?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let lastAccessedAt: Date?
    public let metadata: [String: AnyJSON]?
}
```

### Removed types

- `SignedURL` — doc comment already marks it as backward-compatibility only; no current API returns it

---

## Section 3 — Method Signatures

### `expiresIn: Int` → `Duration`

`Swift.Duration` is a standard library type available since Swift 5.7 with no platform availability restriction. The SDK targets Swift 6.1+, so no `@available` guard is needed. Seconds are extracted via `Int(expiresIn.components.seconds)`.

### `download` overload collapse

Three methods each had two overloads (`download: String?` + `download: Bool`). Six overloads collapse to three single methods using `DownloadBehavior? = nil`.

```swift
// createSignedURL: 2 overloads → 1
func createSignedURL(
    path: String,
    expiresIn: Duration,
    download: DownloadBehavior? = nil,
    transform: TransformOptions? = nil,
    cacheNonce: String? = nil
) async throws -> URL

// createSignedURLs: 2 overloads → 1
func createSignedURLs(
    paths: [String],
    expiresIn: Duration,
    download: DownloadBehavior? = nil,
    cacheNonce: String? = nil
) async throws -> [SignedURLResult]

// getPublicURL: 2 overloads → 1
func getPublicURL(
    path: String,
    download: DownloadBehavior? = nil,
    options: TransformOptions? = nil,
    cacheNonce: String? = nil
) throws -> URL
```

### `uploadToSignedURL` — normalize default options

```swift
// Before: FileOptions? = nil
// After: FileOptions = FileOptions()  (consistent with upload/update)
func uploadToSignedURL(_ path: String, token: String, data: Data,
    options: FileOptions = FileOptions()) async throws -> SignedURLUploadResponse

func uploadToSignedURL(_ path: String, token: String, fileURL: URL,
    options: FileOptions = FileOptions()) async throws -> SignedURLUploadResponse
```

### `info` return type

```swift
func info(path: String) async throws -> FileInfo   // was FileObjectV2
```

---

## Section 4 — Upload Progress Reporting

### Design goals

- Common case (`try await bucket.upload(...)`) must not regress in ergonomics
- Progress is opt-in; zero cost when unused
- No main-actor assumption — callers decide their dispatch context
- Applied uniformly to all six upload-family methods

### `UploadProgress` type

```swift
public struct UploadProgress: Sendable {
    public let totalBytesSent: Int64
    public let totalBytesExpectedToSend: Int64

    public var fractionCompleted: Double {
        guard totalBytesExpectedToSend > 0 else { return 0 }
        return Double(totalBytesSent) / Double(totalBytesExpectedToSend)
    }
}
```

### Method signature (trailing closure, optional)

The `progress` parameter is `@Sendable` (not `@MainActor`) so the SDK does not force a
main-thread dispatch on callers that do not need it.

```swift
@discardableResult
func upload(
    _ path: String,
    data: Data,
    options: FileOptions = FileOptions(),
    progress: (@Sendable (UploadProgress) -> Void)? = nil
) async throws -> FileUploadResponse
```

### Call-site ergonomics

```swift
// Common case — identical to today
let response = try await bucket.upload("photo.jpg", data: imageData)

// With progress — trailing closure syntax
let response = try await bucket.upload("photo.jpg", data: imageData) { progress in
    print("\(Int(progress.fractionCompleted * 100))%")
}

// With UI update on main actor
let response = try await bucket.upload("video.mp4", fileURL: localURL) { progress in
    Task { @MainActor in
        progressBar.progress = Float(progress.fractionCompleted)
    }
}
```

### Scope

| Method | `progress` closure |
|---|---|
| `upload(_ path:, data:, options:)` | yes |
| `upload(_ path:, fileURL:, options:)` | yes |
| `update(_ path:, data:, options:)` | yes |
| `update(_ path:, fileURL:, options:)` | yes |
| `uploadToSignedURL(_:token:data:options:)` | yes |
| `uploadToSignedURL(_:token:fileURL:options:)` | yes |

### Implementation approach

`URLSession.upload(for:from:delegate:)` and `URLSession.upload(for:fromFile:delegate:)`
accept a `URLSessionTaskDelegate` in Swift concurrency. A lightweight `UploadProgressDelegate`
class captures the `progress` closure and forwards
`urlSession(_:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)` calls to it.
No global session delegate is required; the delegate object is scoped to the single upload task.

---

## Change summary

### New types
| Type | Purpose |
|---|---|
| `StorageByteCount` | Type-safe byte count with `.kilobytes()`, `.megabytes()`, `.gigabytes()` factory methods |
| `ResizeMode` | Replaces `TransformOptions.resize: String?` |
| `ImageFormat` | Replaces `TransformOptions.format: String?` |
| `SortOrder` | Replaces `SortBy.order: String?` |
| `DownloadBehavior` | Replaces `download: String?` / `download: Bool` overload pairs |
| `UploadProgress` | Progress reporting for upload-family methods |

### Modified types
| Type | Change |
|---|---|
| `BucketOptions` | `public` → `isPublic`; `fileSizeLimit: String?` → `StorageByteCount?` |
| `FileOptions` | Remove `duplex`, `headers`; `cacheControl` stays `String` |
| `TransformOptions` | `resize: ResizeMode?`; `format: ImageFormat?` |
| `SortBy` | `order: SortOrder?` |
| `SearchOptions` | `prefix` made `internal` |

### Removed types
| Type | Reason |
|---|---|
| `SignedURL` | Legacy, no current API returns it |
| `FileObjectV2` | Renamed to `FileInfo` |

### Kept unchanged (after backend verification)
| Field | Reason |
|---|---|
| `StorageError.statusCode: String?` | Backend sends status code as string |
| `FileOptions.cacheControl: String` | Backend accepts full Cache-Control strings, not just seconds |
