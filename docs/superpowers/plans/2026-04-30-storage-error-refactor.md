# Storage Error Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat `StorageError` struct with a richer struct + `StorageErrorCode` type that gives callers typed codes, an `Int` status code, full HTTP context, and convenience helpers — while ensuring only `StorageError` ever escapes Storage operations.

**Architecture:** `StorageError` stays a struct (forward-compatible: no enum cases to break callers). A new `StorageErrorCode: RawRepresentable` companion holds static constants for known server codes, following the same pattern as `Auth.ErrorCode`. A private `ServerErrorResponse: Decodable` handles JSON decoding so `StorageError` itself no longer needs `Decodable`. `translateStorageError` is consolidated into `StorageClient` (promoted from `private` to `internal`) and always produces a `StorageError` — `HTTPError` never escapes.

**Tech Stack:** Swift 6.1, XCTest, `swift-format` for formatting, `make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild` for running tests.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `Sources/Storage/StorageError.swift` | **Rewrite** | `StorageErrorCode` struct + static constants; `StorageError` struct + convenience helpers + static factories |
| `Sources/Storage/StorageClient.swift` | **Modify** | Add `ServerErrorResponse` (private); promote `translateStorageError` to `internal`; update implementation to always produce `StorageError` |
| `Sources/Storage/StorageFileAPI.swift` | **Modify** | Delete duplicate `translateStorageError`; call `client.translateStorageError`; simplify `exists(path:)`; replace old `StorageError` init |
| `Tests/StorageTests/StorageErrorTests.swift` | **Rewrite** | Tests for `StorageErrorCode` + `StorageError` struct, helpers, and static factories |
| `Tests/StorageTests/StorageFileAPITests.swift` | **Modify** | Fix `testNonSuccessStatusCodeWithNonJSONResponse` to catch `StorageError` |

---

## Task 1: Rewrite `Sources/Storage/StorageError.swift`

**Files:**
- Modify: `Sources/Storage/StorageError.swift`

This replaces the old flat struct (with `statusCode: String?`, `error: String?`, `Decodable`) with the new `StorageErrorCode` type and a richer `StorageError` struct. After this task, `StorageClient` and `StorageFileAPI` will fail to compile — that is expected and fixed in Tasks 3 and 4.

- [ ] **Step 1: Replace the file contents**

```swift
//
//  StorageError.swift
//  Storage
//
//  Created by Guilherme Souza on 22/05/24.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A typed code identifying the specific error returned by the Storage server.
///
/// Known server error strings are exposed as static constants. Because the server may return codes
/// not listed here (e.g. when the SDK is older than the server), the type is open-ended: any
/// unrecognised string is representable without breaking existing `switch` statements.
///
/// ## Example
///
/// ```swift
/// catch let error as StorageError {
///   if error.errorCode == .objectNotFound { /* handle missing object */ }
/// }
/// ```
public struct StorageErrorCode: RawRepresentable, Sendable, Hashable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(_ rawValue: String) {
    self.init(rawValue: rawValue)
  }
}

extension StorageErrorCode {
  /// Fallback used when the server returns an unrecognised code or a non-JSON body.
  public static let unknown = StorageErrorCode("unknown")

  // MARK: - Authentication / authorisation

  /// No API key was supplied with the request.
  public static let noApiKey = StorageErrorCode("NoApiKeyFound")
  /// The JWT supplied with the request is invalid.
  public static let invalidJWT = StorageErrorCode("InvalidJWT")
  /// The request was rejected because the caller is not authorised.
  public static let unauthorized = StorageErrorCode("Unauthorized")

  // MARK: - Object / bucket

  /// Generic not-found response (no further specificity from the server).
  public static let notFound = StorageErrorCode("NotFound")
  /// The requested object does not exist.
  public static let objectNotFound = StorageErrorCode("ObjectNotFound")
  /// The requested bucket does not exist.
  public static let bucketNotFound = StorageErrorCode("BucketNotFound")
  /// An object at the given path already exists and upsert was not requested.
  public static let objectAlreadyExists = StorageErrorCode("Duplicate")
  /// A bucket with the given name already exists.
  public static let bucketAlreadyExists = StorageErrorCode("BucketAlreadyExists")
  /// The bucket name does not meet naming requirements.
  public static let invalidBucketName = StorageErrorCode("InvalidBucketName")

  // MARK: - Upload

  /// The uploaded file exceeds the configured size limit.
  public static let entityTooLarge = StorageErrorCode("EntityTooLarge")
  /// The MIME type of the uploaded file is not allowed.
  public static let invalidMimeType = StorageErrorCode("InvalidMimeType")
  /// The request did not include a Content-Type header.
  public static let missingContentType = StorageErrorCode("MissingContentType")

  // MARK: - Client-side synthetic codes (no HTTP response)

  /// The signed upload URL returned by the server contained no upload token.
  public static let noTokenReturned = StorageErrorCode("noTokenReturned")
}

/// An error thrown by the Supabase Storage API.
///
/// All Storage operations throw ``StorageError`` on failure. Use ``message`` for a human-readable
/// description, ``errorCode`` to identify the specific failure kind, and ``statusCode`` for the
/// HTTP status when the error originated from a server response.
///
/// Adding new ``StorageErrorCode`` constants in future SDK versions is not a breaking change.
///
/// ## Example
///
/// ```swift
/// do {
///   try await storage.from("avatars").upload("image.png", data: data)
/// } catch let error as StorageError {
///   switch error.errorCode {
///   case .objectAlreadyExists:
///     print("File already exists — use upsert: true to overwrite")
///   case .entityTooLarge:
///     print("File is too large")
///   default:
///     print("Storage error \(error.statusCode ?? -1): \(error.message)")
///   }
/// }
/// ```
public struct StorageError: Error, Sendable {
  /// A human-readable description of what went wrong.
  public let message: String

  /// A typed error code identifying the specific failure.
  ///
  /// Set to ``StorageErrorCode/unknown`` when the server returns an unrecognised code or a
  /// non-JSON response body.
  public let errorCode: StorageErrorCode

  /// The HTTP status code returned by the server.
  ///
  /// `nil` for client-side errors that have no associated HTTP response
  /// (e.g. ``StorageError/noTokenReturned``).
  public let statusCode: Int?

  /// The raw HTTP response, available for advanced debugging.
  ///
  /// `nil` for client-side errors.
  public let underlyingResponse: HTTPURLResponse?

  /// The raw response body, available for advanced debugging.
  ///
  /// `nil` for client-side errors.
  public let underlyingData: Data?

  public init(
    message: String,
    errorCode: StorageErrorCode,
    statusCode: Int? = nil,
    underlyingResponse: HTTPURLResponse? = nil,
    underlyingData: Data? = nil
  ) {
    self.message = message
    self.errorCode = errorCode
    self.statusCode = statusCode
    self.underlyingResponse = underlyingResponse
    self.underlyingData = underlyingData
  }
}

extension StorageError {
  /// `true` when the error indicates that the requested object or bucket does not exist.
  ///
  /// Covers HTTP status codes 400 and 404 as well as the explicit error codes
  /// ``StorageErrorCode/objectNotFound``, ``StorageErrorCode/bucketNotFound``, and
  /// ``StorageErrorCode/notFound``.
  public var isNotFound: Bool {
    statusCode == 400 || statusCode == 404
      || errorCode == .objectNotFound
      || errorCode == .bucketNotFound
      || errorCode == .notFound
  }

  /// `true` when the error indicates an authentication or authorisation failure (status 401 or 403).
  public var isUnauthorized: Bool {
    statusCode == 401 || statusCode == 403
  }
}

extension StorageError {
  /// Thrown when the signed upload URL returned by the server contains no upload token.
  public static let noTokenReturned = StorageError(
    message: "No token returned by API",
    errorCode: .noTokenReturned
  )
}

extension StorageError: LocalizedError {
  public var errorDescription: String? {
    message
  }
}
```

---

## Task 2: Rewrite `Tests/StorageTests/StorageErrorTests.swift`

**Files:**
- Modify: `Tests/StorageTests/StorageErrorTests.swift`

The existing tests cover the old `Decodable` struct. Replace them entirely with tests for `StorageErrorCode` and the new `StorageError` API. The project still won't fully compile yet (Tasks 3–5 fix that), but these tests define the contract.

- [ ] **Step 1: Replace the file contents**

```swift
import Foundation
import XCTest

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import Storage

final class StorageErrorTests: XCTestCase {

  // MARK: - StorageErrorCode

  func testErrorCodeRawRepresentable() {
    let code = StorageErrorCode("ObjectNotFound")
    XCTAssertEqual(code.rawValue, "ObjectNotFound")
  }

  func testErrorCodeInitFromRawValue() {
    let code = StorageErrorCode(rawValue: "BucketNotFound")
    XCTAssertEqual(code, .bucketNotFound)
  }

  func testErrorCodeEquality() {
    XCTAssertEqual(StorageErrorCode("ObjectNotFound"), .objectNotFound)
    XCTAssertNotEqual(StorageErrorCode("ObjectNotFound"), .bucketNotFound)
  }

  func testUnknownCodeRoundTrips() {
    // A code returned by a newer server that this SDK doesn't know about
    // must not crash or match any known constant.
    let code = StorageErrorCode("SomeFutureCode")
    XCTAssertEqual(code.rawValue, "SomeFutureCode")
    XCTAssertNotEqual(code, .unknown)
  }

  // MARK: - StorageError initialisation

  func testAPIErrorWithFullHTTPContext() throws {
    let response = try XCTUnwrap(
      HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 404,
        httpVersion: nil,
        headerFields: nil
      )
    )
    let data = Data("not found".utf8)

    let error = StorageError(
      message: "Object not found",
      errorCode: .objectNotFound,
      statusCode: 404,
      underlyingResponse: response,
      underlyingData: data
    )

    XCTAssertEqual(error.message, "Object not found")
    XCTAssertEqual(error.errorCode, .objectNotFound)
    XCTAssertEqual(error.statusCode, 404)
    XCTAssertEqual(error.underlyingResponse?.statusCode, 404)
    XCTAssertEqual(error.underlyingData, data)
  }

  func testClientSideErrorHasNoHTTPContext() {
    let error = StorageError.noTokenReturned
    XCTAssertEqual(error.message, "No token returned by API")
    XCTAssertEqual(error.errorCode, .noTokenReturned)
    XCTAssertNil(error.statusCode)
    XCTAssertNil(error.underlyingResponse)
    XCTAssertNil(error.underlyingData)
  }

  // MARK: - LocalizedError

  func testErrorDescriptionEqualsMessage() {
    let error = StorageError(
      message: "Bucket not found",
      errorCode: .bucketNotFound,
      statusCode: 404
    )
    XCTAssertEqual(error.errorDescription, "Bucket not found")
  }

  // MARK: - isNotFound

  func testIsNotFoundStatus404() {
    let error = StorageError(message: "x", errorCode: .unknown, statusCode: 404)
    XCTAssertTrue(error.isNotFound)
  }

  func testIsNotFoundStatus400() {
    let error = StorageError(message: "x", errorCode: .unknown, statusCode: 400)
    XCTAssertTrue(error.isNotFound)
  }

  func testIsNotFoundObjectNotFoundCode() {
    // errorCode alone can trigger isNotFound regardless of status
    let error = StorageError(message: "x", errorCode: .objectNotFound, statusCode: 200)
    XCTAssertTrue(error.isNotFound)
  }

  func testIsNotFoundBucketNotFoundCode() {
    let error = StorageError(message: "x", errorCode: .bucketNotFound, statusCode: 200)
    XCTAssertTrue(error.isNotFound)
  }

  func testIsNotFoundGenericNotFoundCode() {
    let error = StorageError(message: "x", errorCode: .notFound, statusCode: 200)
    XCTAssertTrue(error.isNotFound)
  }

  func testIsNotFoundFalseForServerError() {
    let error = StorageError(message: "x", errorCode: .unknown, statusCode: 500)
    XCTAssertFalse(error.isNotFound)
  }

  // MARK: - isUnauthorized

  func testIsUnauthorized401() {
    let error = StorageError(message: "x", errorCode: .unauthorized, statusCode: 401)
    XCTAssertTrue(error.isUnauthorized)
  }

  func testIsUnauthorized403() {
    let error = StorageError(message: "x", errorCode: .unauthorized, statusCode: 403)
    XCTAssertTrue(error.isUnauthorized)
  }

  func testIsUnauthorizedFalseForOtherStatus() {
    let error = StorageError(message: "x", errorCode: .objectNotFound, statusCode: 404)
    XCTAssertFalse(error.isUnauthorized)
  }
}
```

---

## Task 3: Update `Sources/Storage/StorageClient.swift`

**Files:**
- Modify: `Sources/Storage/StorageClient.swift:300-310`

Two changes:
1. Replace the `private translateStorageError` implementation with an `internal` version that always produces `StorageError` (never `HTTPError`).
2. Add a private `ServerErrorResponse: Decodable` struct to handle JSON decoding.

- [ ] **Step 1: Replace the `translateStorageError` method (lines 300–310)**

Find this block:
```swift
  private func translateStorageError(_ error: any Error) -> any Error {
    guard case HTTPClientError.responseError(let response, let data) = error else {
      return error
    }

    if let storageError = try? decoder.decode(StorageError.self, from: data) {
      return storageError
    }

    return HTTPError(data: data, response: response)
  }
```

Replace with:
```swift
  func translateStorageError(_ error: any Error) -> any Error {
    guard case HTTPClientError.responseError(let response, let data) = error else {
      return error
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

- [ ] **Step 2: Add `ServerErrorResponse` after the `translateStorageError` method**

Directly after the closing brace of `translateStorageError`, add:

```swift
  private struct ServerErrorResponse: Decodable {
    let message: String
    let error: String?
    /// The server sends the status code as a JSON string, e.g. `"404"`.
    let statusCode: String?
  }
```

---

## Task 4: Update `Sources/Storage/StorageFileAPI.swift`

**Files:**
- Modify: `Sources/Storage/StorageFileAPI.swift`

Three independent changes within this file:

### 4a — Delete duplicate `translateStorageError` and update its call site

- [ ] **Step 1: Replace the call site (around line 1064)**

Find:
```swift
      throw translateStorageError(error)
```
(inside the `_upload` / `_uploadToSignedURL` catch block — the line that calls the private copy)

Replace with:
```swift
      throw client.translateStorageError(error)
```

- [ ] **Step 2: Delete the private `translateStorageError` method (around lines 1093–1107)**

Find and remove this entire method:
```swift
  private func translateStorageError(_ error: any Error) -> any Error {
    guard case HTTPClientError.responseError(let response, let data) = error
    else {
      return error
    }

    if let storageError = try? client.decoder.decode(
      StorageError.self,
      from: data
    ) {
      return storageError
    }

    return HTTPError(data: data, response: response)
  }
```

### 4b — Simplify `exists(path:)` (around lines 730–751)

- [ ] **Step 3: Replace the catch block in `exists(path:)`**

Find:
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

      if let statusCode, [400, 404].contains(statusCode) {
        return false
      }

      throw error
    }
```

Replace with:
```swift
    } catch let error as StorageError where error.isNotFound {
      return false
    }
```

### 4c — Replace the old `StorageError` memberwise init (around line 872)

- [ ] **Step 4: Replace the old `StorageError` initialiser call**

Find:
```swift
      throw StorageError(
        statusCode: nil,
        message: "No token returned by API",
        error: nil
      )
```

Replace with:
```swift
      throw StorageError.noTokenReturned
```

---

## Task 5: Update `Tests/StorageTests/StorageFileAPITests.swift`

**Files:**
- Modify: `Tests/StorageTests/StorageFileAPITests.swift:506-513`

The `testNonSuccessStatusCodeWithNonJSONResponse` test currently catches `HTTPError` because the old translation code returned `HTTPError` when the response body was not valid JSON. With the new `translateStorageError`, a non-JSON body produces a `StorageError` with `.unknown` code instead.

- [ ] **Step 1: Replace the catch clause**

Find:
```swift
    } catch let error as HTTPError {
      XCTAssertEqual(error.data, Data("error".utf8))
      XCTAssertEqual(error.response.statusCode, 412)
    }
```

Replace with:
```swift
    } catch let error as StorageError {
      XCTAssertEqual(error.errorCode, .unknown)
      XCTAssertEqual(error.statusCode, 412)
      XCTAssertEqual(error.underlyingData, Data("error".utf8))
    }
```

---

## Task 6: Build, run tests, and commit

**Files:** None modified — verification and commit only.

- [ ] **Step 1: Verify the package compiles**

```bash
swift build 2>&1 | head -40
```

Expected: `Build complete!` with no errors. If there are errors, they indicate a missed call site — fix before continuing.

- [ ] **Step 2: Run the Storage test suite**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild 2>&1 | grep -E "StorageTests|error:|warning:|Test Suite|passed|failed" | tail -30
```

Expected: all `StorageTests` targets pass. No `error:` lines.

- [ ] **Step 3: Format changed files**

```bash
swift-format format --in-place \
  Sources/Storage/StorageError.swift \
  Sources/Storage/StorageClient.swift \
  Sources/Storage/StorageFileAPI.swift \
  Tests/StorageTests/StorageErrorTests.swift \
  Tests/StorageTests/StorageFileAPITests.swift
```

- [ ] **Step 4: Commit**

```bash
git add \
  Sources/Storage/StorageError.swift \
  Sources/Storage/StorageClient.swift \
  Sources/Storage/StorageFileAPI.swift \
  Tests/StorageTests/StorageErrorTests.swift \
  Tests/StorageTests/StorageFileAPITests.swift
git commit -m "$(cat <<'EOF'
refactor(storage): replace StorageError struct with typed StorageErrorCode

- Adds StorageErrorCode (RawRepresentable) with static constants for all
  known server error strings; new constants are never a breaking change
- StorageError gains errorCode: StorageErrorCode, statusCode: Int?,
  underlyingResponse, underlyingData, isNotFound, isUnauthorized
- Removes Decodable conformance; ServerErrorResponse (private) handles
  JSON decoding in translateStorageError
- translateStorageError consolidated to StorageClient (internal); always
  produces StorageError — HTTPError no longer escapes Storage operations
- exists(path:) simplified to a single catch clause using isNotFound

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
