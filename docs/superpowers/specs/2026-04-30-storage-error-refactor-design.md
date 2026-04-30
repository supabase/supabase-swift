# StorageError Refactor — Design Spec

**Date:** 2026-04-30  
**Branch:** `refactor/storage-http-client`  
**Scope:** `Sources/Storage/` and `Tests/StorageTests/` only. No other modules are touched.

---

## Problem Statement

The current `StorageError` has four issues that hurt DX and correctness:

1. **Two types to catch.** When the server returns a non-JSON error body, `HTTPError` leaks out of Storage operations. Callers must write `catch let error as StorageError` AND `catch let error as HTTPError`.
2. **`statusCode` is `String?`.** The server sends it as a JSON string; callers constantly do `error.statusCode.flatMap(Int.init)` to use it.
3. **No typed error codes.** The `error: String?` field is an unstructured string with no static constants; callers compare against raw string literals.
4. **`translateStorageError` is duplicated** verbatim in both `StorageClient` and `StorageFileAPI`.

---

## Design Goals

- One type to catch per Storage operation: `StorageError`.
- Typed, open-ended error codes that never produce breaking changes when new codes are added.
- `statusCode` exposed as `Int?`, not `String?`.
- Full HTTP context (`underlyingResponse`, `underlyingData`) always reachable for debugging.
- Convenience helpers for the most common status checks (`isNotFound`, `isUnauthorized`).
- No breaking changes from adding new error codes in future SDK versions.

---

## Non-Goals

- No changes to Auth, PostgREST, Functions, or Realtime.
- No shared cross-module base type (deferred to the future cross-module unification).
- No changes to how non-HTTP errors (network timeouts, `CancellationError`, `URLError`) propagate — they continue to pass through unchanged.

---

## Design

### `StorageErrorCode`

A `RawRepresentable` struct over `String`, identical in structure to `Auth.ErrorCode`. Static constants are provided for all known server error strings. New constants can be added in minor releases without any call-site breakage.

```swift
public struct StorageErrorCode: RawRepresentable, Sendable, Hashable {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.init(rawValue: rawValue) }
}

extension StorageErrorCode {
  // Fallbacks
  public static let unknown             = StorageErrorCode("unknown")

  // Authentication / authorization
  public static let noApiKey            = StorageErrorCode("NoApiKeyFound")
  public static let invalidJWT          = StorageErrorCode("InvalidJWT")
  public static let unauthorized        = StorageErrorCode("Unauthorized")

  // Object / bucket errors
  public static let notFound            = StorageErrorCode("NotFound")
  public static let objectNotFound      = StorageErrorCode("ObjectNotFound")
  public static let bucketNotFound      = StorageErrorCode("BucketNotFound")
  public static let objectAlreadyExists = StorageErrorCode("Duplicate")
  public static let bucketAlreadyExists = StorageErrorCode("BucketAlreadyExists")
  public static let invalidBucketName   = StorageErrorCode("InvalidBucketName")

  // Upload errors
  public static let entityTooLarge      = StorageErrorCode("EntityTooLarge")
  public static let invalidMimeType     = StorageErrorCode("InvalidMimeType")
  public static let missingContentType  = StorageErrorCode("MissingContentType")

  // Client-side synthetic codes (no HTTP response)
  public static let noTokenReturned     = StorageErrorCode("noTokenReturned")
}
```

### `StorageError`

Stays a `struct` — not an `enum`. Adding new static error code constants or new factory methods in future versions is not a breaking change.

```swift
public struct StorageError: Error, LocalizedError, Sendable {
  /// Human-readable description of the failure.
  public let message: String

  /// Typed error code. `.unknown` when the server returns an unrecognised code.
  public let errorCode: StorageErrorCode

  /// HTTP status code. `nil` for client-side errors that have no HTTP response.
  public let statusCode: Int?

  /// Raw HTTP response for debugging. `nil` for client-side errors.
  public let underlyingResponse: HTTPURLResponse?

  /// Raw response body for debugging. `nil` for client-side errors.
  public let underlyingData: Data?
}
```

**`LocalizedError` conformance:**
```swift
public var errorDescription: String? { message }
```

**Convenience helpers:**
```swift
extension StorageError {
  /// True when the server reports that the object or bucket does not exist
  /// (status 400 or 404, or an objectNotFound / bucketNotFound error code).
  public var isNotFound: Bool {
    statusCode == 400 || statusCode == 404 ||
    errorCode == .objectNotFound || errorCode == .bucketNotFound ||
    errorCode == .notFound
  }

  /// True when the server reports an authentication or authorisation failure (status 401 or 403).
  public var isUnauthorized: Bool {
    statusCode == 401 || statusCode == 403
  }
}
```

**Client-side static factories** (no HTTP response):
```swift
extension StorageError {
  static let noTokenReturned = StorageError(
    message: "No token returned by API",
    errorCode: .noTokenReturned
  )
}
```

**Not `Decodable` directly.** A private `ServerErrorResponse: Decodable` struct in `StorageClient.swift` handles JSON decoding and constructs `StorageError` values. The old `Decodable` conformance is removed.

```swift
// Private — not part of the public API
private struct ServerErrorResponse: Decodable {
  let message: String
  let error: String?       // short code string → StorageErrorCode
  let statusCode: String?  // server sends as string; we parse to Int
}
```

---

## Error Translation

`translateStorageError` is consolidated into a **single `internal` method on `StorageClient`**. The duplicate private copy in `StorageFileAPI` is deleted; `StorageFileAPI` calls `client.translateStorageError(_:)` instead.

```swift
// StorageClient.swift — internal so StorageFileAPI can use it
func translateStorageError(_ error: any Error) -> any Error {
  guard case HTTPClientError.responseError(let response, let data) = error else {
    return error  // URLError, CancellationError, etc. pass through unchanged
  }

  let decoded = try? decoder.decode(ServerErrorResponse.self, from: data)
  return StorageError(
    message: decoded?.message ?? String(data: data, encoding: .utf8) ?? "Unknown error",
    errorCode: decoded?.error.map(StorageErrorCode.init(_:)) ?? .unknown,
    statusCode: decoded?.statusCode.flatMap(Int.init) ?? response.statusCode,
    underlyingResponse: response,
    underlyingData: data
  )
}
```

**Invariant:** Every `HTTPClientError.responseError` becomes a `StorageError`. `HTTPError` never escapes a Storage operation.

---

## Call-Site Improvements

### `exists(path:)` in `StorageFileAPI`

Before (3-branch status extraction across 3 types):
```swift
} catch {
  var statusCode: Int?
  if let error = error as? StorageError {
    statusCode = error.statusCode.flatMap(Int.init)
  } else if let error = error as? HTTPError {
    statusCode = error.response.statusCode
  } else if case HTTPClientError.responseError(let response, _) = error {
    statusCode = response.statusCode
  }
  if let statusCode, [400, 404].contains(statusCode) { return false }
  throw error
}
```

After:
```swift
} catch let error as StorageError where error.isNotFound {
  return false
}
```

### `createSignedUploadURL(path:options:)` in `StorageFileAPI`

Before:
```swift
throw StorageError(statusCode: nil, message: "No token returned by API", error: nil)
```

After:
```swift
throw StorageError.noTokenReturned
```

---

## Breaking Changes

This refactor is intentionally breaking. It is scoped to the `refactor/storage-http-client` branch where breaking changes are already expected.

| What changes | Old | New |
|---|---|---|
| `statusCode` type | `String?` | `Int?` |
| `error` property | `String?` | removed; replaced by `errorCode: StorageErrorCode` |
| `Decodable` conformance | present | removed |
| Memberwise initializer | `StorageError(statusCode:message:error:)` | `StorageError(message:errorCode:statusCode:underlyingResponse:underlyingData:)` |
| Non-JSON HTTP errors | throw `HTTPError` | throw `StorageError` (with `.unknown` code) |

**Not breaking:** Adding new `StorageErrorCode` static constants in future releases. Adding new static factory methods on `StorageError`.

---

## Test Changes

### `Tests/StorageTests/StorageErrorTests.swift`
Full rewrite:
- Tests for `StorageErrorCode` equality and `RawRepresentable` init.
- Tests for `StorageError` struct initialization with and without HTTP context.
- Tests for `isNotFound` and `isUnauthorized` helpers.
- Tests for `errorDescription` / `LocalizedError` conformance.
- Tests for the translation path (JSON body → `StorageError`, non-JSON body → `StorageError` with `.unknown` code).

### `Tests/StorageTests/StorageFileAPITests.swift`
- `testNonSuccessStatusCodeWithNonJSONResponse`: change `catch let error as HTTPError` to `catch let error as StorageError`; assert `error.errorCode == .unknown` and `error.statusCode == 412`.

---

## File Summary

| File | Action |
|---|---|
| `Sources/Storage/StorageError.swift` | Full rewrite — new `StorageErrorCode` struct + refactored `StorageError` struct |
| `Sources/Storage/StorageClient.swift` | Add private `ServerErrorResponse`; make `translateStorageError` internal; remove duplicate |
| `Sources/Storage/StorageFileAPI.swift` | Remove `translateStorageError`; call `client.translateStorageError`; simplify `exists`; use `StorageError.noTokenReturned` |
| `Tests/StorageTests/StorageErrorTests.swift` | Full rewrite for new structure |
| `Tests/StorageTests/StorageFileAPITests.swift` | Update one `catch` clause |
