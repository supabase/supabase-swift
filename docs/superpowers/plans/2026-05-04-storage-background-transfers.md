# Storage Background Transfers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add TUS resumable uploads and background-capable downloads to `Sources/Storage`, surfaced through a unified `StorageTransferTask<Success>` handle with `AsyncSequence`-based progress and `async throws` result access.

**Architecture:** Two internal engines — a `TUSUploadEngine` actor for all uploads (POST→PATCH loop via TUS 1.0.0) and a `DownloadSessionDelegate` for all downloads (shared `URLSessionDownloadDelegate` routing by task ID). Both feed an `AsyncStream<TransferEvent<Success>>` and an internal `Task<Success, Error>` for multi-caller-safe `.result` access. Uploads and downloads share the public `StorageTransferTask<Success>` type.

**Tech Stack:** Swift 6 strict concurrency, `AsyncStream`, `URLSession` (`.background` optional), `Mocker` for test mocking, Swift Testing (`@Test` / `#expect`). Spec: `docs/superpowers/specs/2026-05-04-storage-background-transfers-design.md`.

**⚠️ Spec correction:** The spec says "add new StorageError cases". `StorageError` is a `struct`, not an enum. New errors are added as `StorageErrorCode` constants + `StorageError` static factory methods (see Task 1).

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/Storage/StorageTransferTask.swift` | `StorageTransferTask<Success>`, `TransferEvent`, `TransferProgress`, typealiases, `mapResult` |
| Create | `Sources/Storage/TUSUploadEngine.swift` | `TUSUploadEngine` actor, `UploadSource`, state machine, TUS protocol |
| Create | `Sources/Storage/DownloadSessionDelegate.swift` | Shared `URLSessionDownloadDelegate`, routing table per task ID |
| Modify | `Sources/Storage/StorageError.swift` | New `StorageErrorCode` constants + `StorageError` static factory methods |
| Modify | `Sources/Storage/StorageClient.swift` | `backgroundDownloadSessionIdentifier` in config; download session + delegate on client; `handleBackgroundEvents` |
| Modify | `Sources/Storage/StorageFileAPI.swift` | Replace `upload`/`update`/`uploadToSignedURL`/`download` signatures; add `downloadData` |
| Create | `Tests/StorageTests/StorageTransferTaskTests.swift` | Unit tests for task type and `mapResult` |
| Create | `Tests/StorageTests/TUSUploadEngineTests.swift` | Unit tests for TUS engine |
| Create | `Tests/StorageTests/DownloadSessionDelegateTests.swift` | Unit tests for download delegate routing |

---

## Task 1: Core transfer types + error codes

**Files:**
- Create: `Sources/Storage/StorageTransferTask.swift`
- Modify: `Sources/Storage/StorageError.swift`
- Create: `Tests/StorageTests/StorageTransferTaskTests.swift`

- [ ] **Step 1.1: Write failing tests for `StorageTransferTask`, `TransferProgress`, and `mapResult`**

Create `Tests/StorageTests/StorageTransferTaskTests.swift`:

```swift
import Foundation
import Testing
@testable import Storage

@Suite struct StorageTransferTaskTests {

  @Test func transferProgressFractionCompleted() {
    let p = TransferProgress(bytesTransferred: 25, totalBytes: 100)
    #expect(p.fractionCompleted == 0.25)
  }

  @Test func transferProgressFractionCompletedWhenTotalIsZero() {
    let p = TransferProgress(bytesTransferred: 0, totalBytes: 0)
    #expect(p.fractionCompleted == 0)
  }

  @Test func eventsStreamDeliversProgressAndCompletion() async throws {
    let task = makeTask(success: "hello")
    var events: [TransferEvent<String>] = []
    for await event in task.events {
      events.append(event)
    }
    #expect(events.count == 2)
    if case .progress(let p) = events[0] {
      #expect(p.bytesTransferred == 10)
    } else {
      Issue.record("Expected .progress as first event")
    }
    if case .completed(let v) = events[1] {
      #expect(v == "hello")
    } else {
      Issue.record("Expected .completed as second event")
    }
  }

  @Test func resultReturnsSuccessValue() async throws {
    let task = makeTask(success: "world")
    let result = try await task.result
    #expect(result == "world")
  }

  @Test func resultThrowsOnFailure() async {
    let task = makeFailingTask(StorageError.cancelled)
    do {
      _ = try await task.result
      Issue.record("Expected throw")
    } catch let error as StorageError {
      #expect(error.errorCode == .cancelled)
    }
  }

  @Test func mapResultTransformsSuccess() async throws {
    let task = makeTask(success: 42)
    let mapped = task.mapResult { "\($0)" }
    let result = try await mapped.result
    #expect(result == "42")
  }

  @Test func mapResultForwardsProgress() async throws {
    let task = makeTask(success: 42)
    let mapped = task.mapResult { $0 * 2 }
    var progressSeen = false
    for await event in mapped.events {
      if case .progress = event { progressSeen = true }
    }
    #expect(progressSeen)
  }

  @Test func mapResultPropagatesFailure() async {
    let task = makeFailingTask(StorageError.cancelled)
    let mapped = task.mapResult { "\($0)" }
    do {
      _ = try await mapped.result
      Issue.record("Expected throw")
    } catch let error as StorageError {
      #expect(error.errorCode == .cancelled)
    }
  }
}

// MARK: - Helpers

private func makeTask<Success: Sendable>(success value: Success) -> StorageTransferTask<Success> {
  let (eventStream, eventsContinuation) = AsyncStream<TransferEvent<Success>>.makeStream()
  let (resultStream, resultContinuation) = AsyncStream<Result<Success, any Error>>.makeStream(
    bufferingPolicy: .bufferingNewest(1))

  let resultTask = Task<Success, any Error> {
    for await r in resultStream { return try r.get() }
    throw StorageError.cancelled
  }

  let task = StorageTransferTask<Success>(
    events: eventStream,
    resultTask: resultTask,
    pause: {},
    resume: {},
    cancel: {}
  )

  eventsContinuation.yield(.progress(TransferProgress(bytesTransferred: 10, totalBytes: 100)))
  eventsContinuation.yield(.completed(value))
  eventsContinuation.finish()
  resultContinuation.yield(.success(value))

  return task
}

private func makeFailingTask<Success: Sendable>(_ error: StorageError) -> StorageTransferTask<Success> {
  let (eventStream, eventsContinuation) = AsyncStream<TransferEvent<Success>>.makeStream()
  let (resultStream, resultContinuation) = AsyncStream<Result<Success, any Error>>.makeStream(
    bufferingPolicy: .bufferingNewest(1))

  let resultTask = Task<Success, any Error> {
    for await r in resultStream { return try r.get() }
    throw StorageError.cancelled
  }

  let task = StorageTransferTask<Success>(
    events: eventStream,
    resultTask: resultTask,
    pause: {},
    resume: {},
    cancel: {}
  )

  eventsContinuation.yield(.failed(error))
  eventsContinuation.finish()
  resultContinuation.yield(.failure(error))

  return task
}
```

- [ ] **Step 1.2: Run tests to confirm they fail**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild 2>&1 | grep -E "error:|StorageTransferTaskTests"
```

Expected: compile errors — `StorageTransferTask`, `TransferProgress`, `TransferEvent` not found.

- [ ] **Step 1.3: Create `Sources/Storage/StorageTransferTask.swift`**

```swift
//
//  StorageTransferTask.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import Foundation

/// A handle to an in-flight upload or download.
///
/// Tasks start immediately on creation and are `@discardableResult` — fire-and-forget works
/// without holding a reference. Hold the task to observe progress or control execution.
///
/// Both `.events` and `.result` are independent: consuming one does not affect the other.
public final class StorageTransferTask<Success: Sendable>: @unchecked Sendable {

  /// A stream of transfer events. Finishes after `.completed` or `.failed`.
  public let events: AsyncStream<TransferEvent<Success>>

  private let _resultTask: Task<Success, any Error>
  private let _pause: @Sendable () -> Void
  private let _resume: @Sendable () -> Void
  private let _cancel: @Sendable () -> Void

  init(
    events: AsyncStream<TransferEvent<Success>>,
    resultTask: Task<Success, any Error>,
    pause: @Sendable @escaping () -> Void,
    resume: @Sendable @escaping () -> Void,
    cancel: @Sendable @escaping () -> Void
  ) {
    self.events = events
    self._resultTask = resultTask
    self._pause = pause
    self._resume = resume
    self._cancel = cancel
  }

  /// Awaits the final result. Safe for concurrent callers — backed by `Task.value`.
  /// Throws `StorageError` on failure or cancellation.
  public var result: Success {
    get async throws { try await _resultTask.value }
  }

  /// Suspends the transfer. For uploads: completes the current in-flight chunk first.
  public func pause() { _pause() }

  /// Resumes a paused transfer. For uploads: HEADs the server to re-sync offset first.
  public func resume() { _resume() }

  /// Cancels the transfer immediately.
  public func cancel() {
    _cancel()
    _resultTask.cancel()
  }
}

extension StorageTransferTask {
  /// Returns a new task that applies `transform` to the success value.
  /// Progress events pass through unchanged. Pause/resume/cancel delegate to `self`.
  func mapResult<NewSuccess: Sendable>(
    _ transform: @Sendable @escaping (Success) throws -> NewSuccess
  ) -> StorageTransferTask<NewSuccess> {
    let (newStream, newContinuation) = AsyncStream<TransferEvent<NewSuccess>>.makeStream()
    let (resultStream, resultContinuation) = AsyncStream<Result<NewSuccess, any Error>>.makeStream(
      bufferingPolicy: .bufferingNewest(1))

    Task {
      for await event in self.events {
        switch event {
        case .progress(let p):
          newContinuation.yield(.progress(p))
        case .completed(let value):
          do {
            let mapped = try transform(value)
            newContinuation.yield(.completed(mapped))
            newContinuation.finish()
            resultContinuation.yield(.success(mapped))
          } catch {
            let storageError = StorageError.fileSystemError(underlying: error)
            newContinuation.yield(.failed(storageError))
            newContinuation.finish()
            resultContinuation.yield(.failure(storageError))
          }
        case .failed(let error):
          newContinuation.yield(.failed(error))
          newContinuation.finish()
          resultContinuation.yield(.failure(error))
        }
      }
      newContinuation.finish()
    }

    let newResultTask = Task<NewSuccess, any Error> {
      for await r in resultStream { return try r.get() }
      throw StorageError.cancelled
    }

    return StorageTransferTask<NewSuccess>(
      events: newStream,
      resultTask: newResultTask,
      pause: self._pause,
      resume: self._resume,
      cancel: self._cancel
    )
  }
}

/// An event emitted during a transfer.
public enum TransferEvent<Success: Sendable>: Sendable {
  case progress(TransferProgress)
  case completed(Success)
  /// Terminal — the stream ends after this event.
  case failed(StorageError)
}

/// Byte-level progress for a transfer.
public struct TransferProgress: Sendable {
  public let bytesTransferred: Int64
  public let totalBytes: Int64

  public var fractionCompleted: Double {
    guard totalBytes > 0 else { return 0 }
    return Double(bytesTransferred) / Double(totalBytes)
  }
}

/// A handle for an upload. Success type is ``FileUploadResponse``.
public typealias StorageUploadTask = StorageTransferTask<FileUploadResponse>

/// A handle for a download. Success type is `URL` — a path to the downloaded file on disk.
public typealias StorageDownloadTask = StorageTransferTask<URL>
```

- [ ] **Step 1.4: Add new `StorageErrorCode` constants and `StorageError` factory methods to `Sources/Storage/StorageError.swift`**

Append to the end of the file (after the `LocalizedError` extension):

```swift
extension StorageErrorCode {
  // MARK: - Transfer errors (client-side)

  /// A network error occurred during a transfer (transient; retriable on resume).
  public static let networkError = StorageErrorCode("NetworkError")
  /// A file system operation (move or read) failed during a transfer.
  public static let fileSystemError = StorageErrorCode("FileSystemError")
  /// The transfer was explicitly cancelled or the enclosing Swift Task was cancelled.
  public static let cancelled = StorageErrorCode("Cancelled")
}

extension StorageError {
  static func networkError(underlying: any Error) -> StorageError {
    StorageError(message: underlying.localizedDescription, errorCode: .networkError)
  }

  static func fileSystemError(underlying: any Error) -> StorageError {
    StorageError(message: underlying.localizedDescription, errorCode: .fileSystemError)
  }

  static let cancelled = StorageError(
    message: "Transfer was cancelled",
    errorCode: .cancelled
  )
}
```

- [ ] **Step 1.5: Run tests to confirm they pass**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild 2>&1 | grep -E "StorageTransferTaskTests|Test.*passed|Test.*failed"
```

Expected: all `StorageTransferTaskTests` pass, no regressions.

- [ ] **Step 1.6: Format and commit**

```bash
make format
git add Sources/Storage/StorageTransferTask.swift Sources/Storage/StorageError.swift Tests/StorageTests/StorageTransferTaskTests.swift
git commit -m "feat(storage): add StorageTransferTask, TransferEvent, TransferProgress types"
```

---

## Task 2: `StorageClientConfiguration` + download session

**Files:**
- Modify: `Sources/Storage/StorageClient.swift` (lines 28–62 for config; StorageClient class body for new properties)

- [ ] **Step 2.1: Add `backgroundDownloadSessionIdentifier` to `StorageClientConfiguration`**

In `Sources/Storage/StorageClient.swift`, locate `StorageClientConfiguration` (lines 28–63). Add a new property after `useNewHostname`:

```swift
/// When set, downloads use `URLSessionConfiguration.background(withIdentifier:)`,
/// allowing transfers to continue while the app is suspended.
///
/// Requires wiring `handleBackgroundEvents(forSessionIdentifier:completionHandler:)` in
/// your `AppDelegate` (see ``StorageClient/handleBackgroundEvents(forSessionIdentifier:completionHandler:)``).
///
/// When `nil` (the default), a standard foreground session is used.
public var backgroundDownloadSessionIdentifier: String?
```

Update the `init` to accept and assign it:

```swift
public init(
  headers: [String: String],
  session: URLSession = URLSession(configuration: .default),
  logger: (any SupabaseLogger)? = nil,
  useNewHostname: Bool = false,
  backgroundDownloadSessionIdentifier: String? = nil
) {
  self.headers = headers
  self.session = session
  self.logger = logger
  self.useNewHostname = useNewHostname
  self.backgroundDownloadSessionIdentifier = backgroundDownloadSessionIdentifier
}
```

- [ ] **Step 2.2: Add empty `DownloadSessionDelegate` stub so `StorageClient` compiles**

`StorageClient` will reference `DownloadSessionDelegate` before it is fully implemented in Task 7.
Create a temporary stub at the top of `Sources/Storage/DownloadSessionDelegate.swift` now:

```swift
//
//  DownloadSessionDelegate.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// Full implementation added in Task 7.
final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  func setBackgroundCompletionHandler(_ handler: @escaping @Sendable () -> Void) {}

  func makeStorageDownloadTask(in session: URLSession, request: URLRequest) -> StorageDownloadTask {
    fatalError("DownloadSessionDelegate not yet implemented — complete Task 7")
  }
}
```

- [ ] **Step 2.3: Add download session + delegate to `StorageClient`**

Inside the `StorageClient` class (after the existing stored properties), add:

```swift
let downloadDelegate: DownloadSessionDelegate
let downloadSession: URLSession
```

In the `package init(url:configuration:tokenProvider:)` initialiser, after the existing setup, add (before `super.init()` or at the end of the init body):

```swift
let downloadDelegate = DownloadSessionDelegate()
self.downloadDelegate = downloadDelegate

let downloadSessionConfig: URLSessionConfiguration =
  configuration.backgroundDownloadSessionIdentifier.map {
    .background(withIdentifier: $0)
  } ?? .default
self.downloadSession = URLSession(
  configuration: downloadSessionConfig,
  delegate: downloadDelegate,
  delegateQueue: nil
)
```

- [ ] **Step 2.4: Add `handleBackgroundEvents` to `StorageClient`**

In `Sources/Storage/StorageClient.swift`, add a public method after `from(_:)`:

```swift
/// Forward background URLSession events from your `AppDelegate` to the Storage client.
///
/// Call this from `application(_:handleEventsForBackgroundURLSession:completionHandler:)`
/// when the `identifier` matches the one configured in ``StorageClientConfiguration/backgroundDownloadSessionIdentifier``.
///
/// ```swift
/// func application(
///   _ application: UIApplication,
///   handleEventsForBackgroundURLSession identifier: String,
///   completionHandler: @escaping () -> Void
/// ) {
///   supabase.storage.handleBackgroundEvents(
///     forSessionIdentifier: identifier,
///     completionHandler: completionHandler
///   )
/// }
/// ```
public func handleBackgroundEvents(
  forSessionIdentifier identifier: String,
  completionHandler: @escaping @Sendable () -> Void
) {
  guard identifier == configuration.backgroundDownloadSessionIdentifier else { return }
  downloadDelegate.setBackgroundCompletionHandler(completionHandler)
}
```

- [ ] **Step 2.5: Build to verify no errors**

```bash
swift build 2>&1 | grep -E "error:|warning:" | head -20
```

Expected: no errors — `DownloadSessionDelegate` now exists as a stub.

- [ ] **Step 2.6: Format and commit**

```bash
make format
git add Sources/Storage/DownloadSessionDelegate.swift Sources/Storage/StorageClient.swift
git commit -m "feat(storage): add backgroundDownloadSessionIdentifier config + download session setup"
```

---

## Task 3: `TUSUploadEngine` — state machine + POST

**Files:**
- Create: `Sources/Storage/TUSUploadEngine.swift`
- Create: `Tests/StorageTests/TUSUploadEngineTests.swift`

- [ ] **Step 3.1: Write failing test for TUS POST**

Create `Tests/StorageTests/TUSUploadEngineTests.swift`:

```swift
import Foundation
import Mocker
import Testing
@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized) struct TUSUploadEngineTests {

  let baseURL = URL(string: "https://example.supabase.co/storage/v1")!
  let uploadURL = URL(string: "https://example.supabase.co/storage/v1/upload/resumable")!
  let locationURL = URL(string: "https://example.supabase.co/storage/v1/upload/resumable/test-id")!

  var client: StorageClient {
    StorageClient(
      url: baseURL,
      configuration: StorageClientConfiguration(
        headers: ["Authorization": "Bearer test-token"],
        session: .mockedSession
      )
    )
  }

  @Test func postCreatesUploadWithCorrectHeaders() async throws {
    var capturedRequest: URLRequest?

    var mock = Mock(
      url: uploadURL,
      dataType: .json,
      statusCode: 201,
      data: [.post: Data()],
      additionalHeaders: ["Location": locationURL.absoluteString]
    )
    mock.onRequest = { request, _ in capturedRequest = request }
    mock.register()

    // Register a PATCH mock so the engine can proceed past POST without error
    Mock(
      url: locationURL,
      dataType: .other("application/offset+octet-stream"),
      statusCode: 200,
      data: [.patch: try! JSONEncoder().encode(FileUploadResponse(id: UUID(), path: "test.txt", fullPath: "bucket/test.txt"))],
      additionalHeaders: ["Upload-Offset": "5"]
    ).register()

    let data = Data("hello".utf8)
    let task = TUSUploadEngine.makeTask(
      bucketId: "bucket",
      path: "test.txt",
      source: .data(data),
      options: FileOptions(contentType: "text/plain", upsert: false),
      client: client
    )
    _ = try await task.result

    let request = try #require(capturedRequest)
    #expect(request.value(forHTTPHeaderField: "Tus-Resumable") == "1.0.0")
    #expect(request.value(forHTTPHeaderField: "Upload-Length") == "5")
    let metadata = try #require(request.value(forHTTPHeaderField: "Upload-Metadata"))
    #expect(metadata.contains("bucketName"))
    #expect(metadata.contains("objectName"))
    #expect(metadata.contains("contentType"))
  }
}

extension URLSession {
  static var mockedSession: URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockingURLProtocol.self]
    return URLSession(configuration: config)
  }
}
```

- [ ] **Step 3.2: Run test to confirm it fails**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild 2>&1 | grep -E "error:|TUSUploadEngineTests"
```

Expected: compile error — `TUSUploadEngine` not found.

- [ ] **Step 3.3: Create `Sources/Storage/TUSUploadEngine.swift`**

```swift
//
//  TUSUploadEngine.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private let tusChunkSize = 6 * 1024 * 1024  // 6 MB — Supabase/S3 minimum

enum UploadSource: Sendable {
  case data(Data)
  case fileURL(URL)

  func totalBytes() throws -> Int64 {
    switch self {
    case .data(let d):
      return Int64(d.count)
    case .fileURL(let url):
      let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
      guard let size = attrs[.size] as? Int64 else {
        throw StorageError(message: "Cannot determine file size", errorCode: .fileSystemError)
      }
      return size
    }
  }

  func readChunk(at offset: Int64, maxSize: Int) throws -> Data {
    switch self {
    case .data(let d):
      let start = Int(offset)
      let end = min(start + maxSize, d.count)
      return d[start..<end]
    case .fileURL(let url):
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      try handle.seek(toOffset: UInt64(offset))
      return try handle.read(upToCount: maxSize)
    }
  }
}

actor TUSUploadEngine {
  enum State {
    case idle
    case creating
    case uploading(uploadURL: URL, offset: Int64)
    case paused(uploadURL: URL, offset: Int64)
    case completed(FileUploadResponse)
    case failed(StorageError)
    case cancelled
  }

  private let bucketId: String
  private let path: String
  private let source: UploadSource
  private let options: FileOptions
  private let client: StorageClient
  private let eventsContinuation: AsyncStream<TransferEvent<FileUploadResponse>>.Continuation
  private let resultContinuation: AsyncStream<Result<FileUploadResponse, any Error>>.Continuation

  private var state: State = .idle
  private var currentUploadTask: Task<Void, Never>?

  init(
    bucketId: String,
    path: String,
    source: UploadSource,
    options: FileOptions,
    client: StorageClient,
    eventsContinuation: AsyncStream<TransferEvent<FileUploadResponse>>.Continuation,
    resultContinuation: AsyncStream<Result<FileUploadResponse, any Error>>.Continuation
  ) {
    self.bucketId = bucketId
    self.path = path
    self.source = source
    self.options = options
    self.client = client
    self.eventsContinuation = eventsContinuation
    self.resultContinuation = resultContinuation
  }

  func start() {
    guard case .idle = state else { return }
    state = .creating
    currentUploadTask = Task { await run() }
  }

  func pause() {
    switch state {
    case .uploading(let url, let offset):
      currentUploadTask?.cancel()
      state = .paused(uploadURL: url, offset: offset)
    default:
      break
    }
  }

  func resume() {
    switch state {
    case .paused(let url, _):
      currentUploadTask = Task { await resumeFromServer(uploadURL: url) }
    default:
      break
    }
  }

  func cancel() {
    currentUploadTask?.cancel()
    state = .cancelled
    let error = StorageError.cancelled
    eventsContinuation.yield(.failed(error))
    eventsContinuation.finish()
    resultContinuation.yield(.failure(error))
  }

  // MARK: - Private

  private func run() async {
    do {
      try Task.checkCancellation()
      let totalBytes = try source.totalBytes()
      let uploadURL = try await createUpload(totalBytes: totalBytes)
      state = .uploading(uploadURL: uploadURL, offset: 0)
      try await uploadChunks(to: uploadURL, from: 0, totalBytes: totalBytes)
    } catch is CancellationError {
      if case .cancelled = state { return }
      cancel()
    } catch let error as StorageError {
      finish(with: .failure(error))
    } catch {
      finish(with: .failure(StorageError.networkError(underlying: error)))
    }
  }

  private func resumeFromServer(uploadURL: URL) async {
    do {
      let serverOffset = try await fetchOffset(uploadURL: uploadURL)
      let totalBytes = try source.totalBytes()
      state = .uploading(uploadURL: uploadURL, offset: serverOffset)
      try await uploadChunks(to: uploadURL, from: serverOffset, totalBytes: totalBytes)
    } catch is CancellationError {
      if case .cancelled = state { return }
      cancel()
    } catch let error as StorageError {
      finish(with: .failure(error))
    } catch {
      finish(with: .failure(StorageError.networkError(underlying: error)))
    }
  }

  private func finish(with result: Result<FileUploadResponse, any Error>) {
    switch result {
    case .success(let response):
      state = .completed(response)
      eventsContinuation.yield(.completed(response))
    case .failure(let error):
      let storageError = error as? StorageError ?? StorageError.networkError(underlying: error)
      state = .failed(storageError)
      eventsContinuation.yield(.failed(storageError))
    }
    eventsContinuation.finish()
    resultContinuation.yield(result.mapError { $0 })
  }

  // MARK: - TUS protocol

  private func createUpload(totalBytes: Int64) async throws -> URL {
    var request = makeRequest(
      url: client.url.appendingPathComponent("upload/resumable"),
      method: "POST"
    )
    request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
    request.setValue("\(totalBytes)", forHTTPHeaderField: "Upload-Length")
    request.setValue(tusMetadata(), forHTTPHeaderField: "Upload-Metadata")
    request.setValue("0", forHTTPHeaderField: "Content-Length")
    if options.upsert {
      request.setValue("true", forHTTPHeaderField: "x-upsert")
    }

    let (_, response) = try await client.http.session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw StorageError(message: "Invalid response", errorCode: .unknown)
    }
    guard httpResponse.statusCode == 201,
      let location = httpResponse.value(forHTTPHeaderField: "Location"),
      let locationURL = URL(string: location)
    else {
      throw StorageError(
        message: "TUS create failed",
        errorCode: .unknown,
        statusCode: httpResponse.statusCode
      )
    }
    return locationURL
  }

  private func fetchOffset(uploadURL: URL) async throws -> Int64 {
    var request = makeRequest(url: uploadURL, method: "HEAD")
    request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")

    let (_, response) = try await client.http.session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
      let offsetString = httpResponse.value(forHTTPHeaderField: "Upload-Offset"),
      let offset = Int64(offsetString)
    else {
      throw StorageError(message: "TUS HEAD failed", errorCode: .unknown)
    }
    return offset
  }

  private func uploadChunks(to uploadURL: URL, from startOffset: Int64, totalBytes: Int64) async throws
  {
    var offset = startOffset
    while offset < totalBytes {
      try Task.checkCancellation()

      let chunk = try source.readChunk(at: offset, maxSize: tusChunkSize)
      guard !chunk.isEmpty else { break }

      var request = makeRequest(url: uploadURL, method: "PATCH")
      request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
      request.setValue("\(offset)", forHTTPHeaderField: "Upload-Offset")
      request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
      request.setValue("\(chunk.count)", forHTTPHeaderField: "Content-Length")

      let (data, response) = try await client.http.session.upload(for: request, from: chunk)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw StorageError(message: "Invalid PATCH response", errorCode: .unknown)
      }

      if httpResponse.statusCode == 409 {
        let serverOffset = try await fetchOffset(uploadURL: uploadURL)
        offset = serverOffset
        continue
      }

      guard httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
        throw StorageError(
          message: "TUS PATCH failed",
          errorCode: .unknown,
          statusCode: httpResponse.statusCode
        )
      }

      guard
        let newOffsetString = httpResponse.value(forHTTPHeaderField: "Upload-Offset"),
        let newOffset = Int64(newOffsetString)
      else {
        throw StorageError(message: "Missing Upload-Offset in PATCH response", errorCode: .unknown)
      }

      offset = newOffset

      eventsContinuation.yield(
        .progress(
          TransferProgress(
            bytesTransferred: offset,
            totalBytes: totalBytes
          )))

      if offset == totalBytes {
        let uploadResponse = try JSONDecoder().decode(FileUploadResponse.self, from: data)
        finish(with: .success(uploadResponse))
        return
      }

      state = .uploading(uploadURL: uploadURL, offset: offset)
    }
  }

  // MARK: - Helpers

  private func makeRequest(url: URL, method: String) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    for (key, value) in client.mergedHeaders([:]) {
      request.setValue(value, forHTTPHeaderField: key)
    }
    return request
  }

  private func tusMetadata() -> String {
    let cleanPath = path.components(separatedBy: "/")
      .filter { !$0.isEmpty }
      .joined(separator: "/")
    let contentType = options.contentType ?? "application/octet-stream"
    let cacheControl = options.cacheControl ?? "3600"
    let entries: [(String, String)] = [
      ("bucketName", bucketId),
      ("objectName", cleanPath),
      ("contentType", contentType),
      ("cacheControl", cacheControl),
    ]
    return entries
      .map { "\($0.0) \(Data($0.1.utf8).base64EncodedString())" }
      .joined(separator: ",")
  }
}

// MARK: - Factory

extension TUSUploadEngine {
  /// Creates a `StorageUploadTask` backed by this engine, starts the upload, and returns the task.
  static func makeTask(
    bucketId: String,
    path: String,
    source: UploadSource,
    options: FileOptions,
    client: StorageClient
  ) -> StorageUploadTask {
    let (eventStream, eventsContinuation) =
      AsyncStream<TransferEvent<FileUploadResponse>>.makeStream()
    let (resultStream, resultContinuation) =
      AsyncStream<Result<FileUploadResponse, any Error>>.makeStream(
        bufferingPolicy: .bufferingNewest(1))

    let engine = TUSUploadEngine(
      bucketId: bucketId,
      path: path,
      source: source,
      options: options,
      client: client,
      eventsContinuation: eventsContinuation,
      resultContinuation: resultContinuation
    )

    let resultTask = Task<FileUploadResponse, any Error> {
      for await r in resultStream { return try r.get() }
      throw StorageError.cancelled
    }

    let task = StorageUploadTask(
      events: eventStream,
      resultTask: resultTask,
      pause: { Task { await engine.pause() } },
      resume: { Task { await engine.resume() } },
      cancel: { Task { await engine.cancel() } }
    )

    Task { await engine.start() }

    return task
  }
}
```

- [ ] **Step 3.4: Run tests to confirm they pass**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild 2>&1 | grep -E "TUSUploadEngineTests|passed|failed"
```

Expected: `postCreatesUploadWithCorrectHeaders` passes.

- [ ] **Step 3.5: Format and commit**

```bash
make format
git add Sources/Storage/TUSUploadEngine.swift Tests/StorageTests/TUSUploadEngineTests.swift
git commit -m "feat(storage): add TUSUploadEngine with POST create and PATCH chunk loop"
```

---

## Task 4: TUS engine — chunk count, progress, 409 re-sync

**Files:**
- Modify: `Tests/StorageTests/TUSUploadEngineTests.swift`

- [ ] **Step 4.1: Write failing tests for chunk count, offsets, and 409 handling**

Add to the `TUSUploadEngineTests` suite:

```swift
@Test func sendsTwoChunksForDataLargerThanChunkSize() async throws {
  // 7 MB data → 2 chunks (6 MB + 1 MB)
  let data = Data(repeating: 0x42, count: 7 * 1024 * 1024)
  var patchCount = 0
  var patchOffsets: [Int64] = []

  Mock(
    url: uploadURL,
    dataType: .json,
    statusCode: 201,
    data: [.post: Data()],
    additionalHeaders: ["Location": locationURL.absoluteString]
  ).register()

  let finalResponse = try JSONEncoder().encode(
    FileUploadResponse(id: UUID(), path: "big.bin", fullPath: "bucket/big.bin"))

  // First PATCH (0..6MB)
  var patch1 = Mock(
    url: locationURL,
    dataType: .other("application/offset+octet-stream"),
    statusCode: 204,
    data: [.patch: Data()],
    additionalHeaders: ["Upload-Offset": "\(6 * 1024 * 1024)"]
  )
  patch1.onRequest = { _, _ in patchCount += 1; patchOffsets.append(0) }

  // Second PATCH (6MB..7MB)
  var patch2 = Mock(
    url: locationURL,
    dataType: .other("application/offset+octet-stream"),
    statusCode: 200,
    data: [.patch: finalResponse],
    additionalHeaders: ["Upload-Offset": "\(7 * 1024 * 1024)"]
  )
  patch2.onRequest = { _, _ in patchCount += 1; patchOffsets.append(Int64(6 * 1024 * 1024)) }

  patch1.register()
  patch2.register()

  let task = TUSUploadEngine.makeTask(
    bucketId: "bucket",
    path: "big.bin",
    source: .data(data),
    options: FileOptions(contentType: "application/octet-stream"),
    client: client
  )
  _ = try await task.result

  #expect(patchCount == 2)
  #expect(patchOffsets == [0, Int64(6 * 1024 * 1024)])
}

@Test func emitsProgressEventsPerChunk() async throws {
  let data = Data(repeating: 0x01, count: 7 * 1024 * 1024)

  Mock(
    url: uploadURL,
    dataType: .json,
    statusCode: 201,
    data: [.post: Data()],
    additionalHeaders: ["Location": locationURL.absoluteString]
  ).register()

  let finalResponse = try JSONEncoder().encode(
    FileUploadResponse(id: UUID(), path: "f.bin", fullPath: "bucket/f.bin"))

  Mock(
    url: locationURL,
    dataType: .other("application/offset+octet-stream"),
    statusCode: 204,
    data: [.patch: Data()],
    additionalHeaders: ["Upload-Offset": "\(6 * 1024 * 1024)"]
  ).register()

  Mock(
    url: locationURL,
    dataType: .other("application/offset+octet-stream"),
    statusCode: 200,
    data: [.patch: finalResponse],
    additionalHeaders: ["Upload-Offset": "\(7 * 1024 * 1024)"]
  ).register()

  let task = TUSUploadEngine.makeTask(
    bucketId: "bucket", path: "f.bin",
    source: .data(data),
    options: FileOptions(contentType: "application/octet-stream"),
    client: client
  )

  var progressFractions: [Double] = []
  for await event in task.events {
    if case .progress(let p) = event {
      progressFractions.append(p.fractionCompleted)
    }
  }
  #expect(progressFractions.count == 2)
  #expect(progressFractions[0] < progressFractions[1])
  #expect(progressFractions[1] == 1.0)
}

@Test func resyncesOffsetOn409() async throws {
  let data = Data(repeating: 0x01, count: 100)
  var headCount = 0

  Mock(
    url: uploadURL,
    dataType: .json,
    statusCode: 201,
    data: [.post: Data()],
    additionalHeaders: ["Location": locationURL.absoluteString]
  ).register()

  // First PATCH → 409
  Mock(
    url: locationURL,
    dataType: .json,
    statusCode: 409,
    data: [.patch: Data()],
    additionalHeaders: [:]
  ).register()

  // HEAD for re-sync
  var headMock = Mock(
    url: locationURL,
    dataType: .json,
    statusCode: 200,
    data: [.head: Data()],
    additionalHeaders: ["Upload-Offset": "0"]
  )
  headMock.onRequest = { _, _ in headCount += 1 }
  headMock.register()

  // Second PATCH (retry from offset 0) → success
  let finalResponse = try JSONEncoder().encode(
    FileUploadResponse(id: UUID(), path: "x.txt", fullPath: "bucket/x.txt"))
  Mock(
    url: locationURL,
    dataType: .other("application/offset+octet-stream"),
    statusCode: 200,
    data: [.patch: finalResponse],
    additionalHeaders: ["Upload-Offset": "100"]
  ).register()

  let task = TUSUploadEngine.makeTask(
    bucketId: "bucket", path: "x.txt",
    source: .data(data),
    options: FileOptions(contentType: "text/plain"),
    client: client
  )
  _ = try await task.result

  #expect(headCount == 1)
}
```

- [ ] **Step 4.2: Run tests to verify they fail (or partially pass)**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild 2>&1 | grep -E "TUSUploadEngineTests|passed|failed"
```

- [ ] **Step 4.3: Run tests again after verifying the implementation handles these cases**

The implementation in Task 3 already handles 409 re-sync, chunk loop, and progress events. If tests fail, inspect the Mocker setup — `Mock` registers match requests in order for the same URL. Ensure each `Mock` is registered before starting the task.

Expected: all three new tests pass.

- [ ] **Step 4.4: Format and commit**

```bash
make format
git add Tests/StorageTests/TUSUploadEngineTests.swift
git commit -m "test(storage): add TUS chunk count, progress, and 409 re-sync tests"
```

---

## Task 5: TUS engine — pause / resume / cancel

**Files:**
- Modify: `Tests/StorageTests/TUSUploadEngineTests.swift`

- [ ] **Step 5.1: Write tests for cancel mid-upload**

Add to the suite:

```swift
@Test func cancelMidUploadEmitsCancelledEvent() async throws {
  let data = Data(repeating: 0x01, count: 7 * 1024 * 1024)

  Mock(
    url: uploadURL,
    dataType: .json,
    statusCode: 201,
    data: [.post: Data()],
    additionalHeaders: ["Location": locationURL.absoluteString]
  ).register()

  // Slow first PATCH (never returns — task will be cancelled before second chunk)
  var slowPatch = Mock(
    url: locationURL,
    dataType: .other("application/offset+octet-stream"),
    statusCode: 204,
    data: [.patch: Data()],
    additionalHeaders: ["Upload-Offset": "\(6 * 1024 * 1024)"]
  )
  slowPatch.delay = DispatchTimeInterval.seconds(60)
  slowPatch.register()

  let task = TUSUploadEngine.makeTask(
    bucketId: "bucket", path: "big.bin",
    source: .data(data),
    options: FileOptions(contentType: "application/octet-stream"),
    client: client
  )

  // Cancel after a short delay
  Task {
    try? await Task.sleep(for: .milliseconds(100))
    task.cancel()
  }

  var lastEvent: TransferEvent<FileUploadResponse>?
  for await event in task.events {
    lastEvent = event
  }

  if case .failed(let error) = lastEvent {
    #expect(error.errorCode == .cancelled)
  } else {
    Issue.record("Expected .failed(.cancelled), got \(String(describing: lastEvent))")
  }
}

@Test func cancelledTaskResultThrows() async throws {
  let data = Data(repeating: 0x01, count: 100)

  Mock(
    url: uploadURL,
    dataType: .json,
    statusCode: 201,
    data: [.post: Data()],
    additionalHeaders: ["Location": locationURL.absoluteString]
  ).register()

  var slowPatch = Mock(
    url: locationURL,
    dataType: .other("application/offset+octet-stream"),
    statusCode: 200,
    data: [.patch: Data()],
    additionalHeaders: ["Upload-Offset": "100"]
  )
  slowPatch.delay = DispatchTimeInterval.seconds(60)
  slowPatch.register()

  let task = TUSUploadEngine.makeTask(
    bucketId: "bucket", path: "f.txt",
    source: .data(data),
    options: FileOptions(contentType: "text/plain"),
    client: client
  )

  Task {
    try? await Task.sleep(for: .milliseconds(100))
    task.cancel()
  }

  do {
    _ = try await task.result
    Issue.record("Expected throw")
  } catch let error as StorageError {
    #expect(error.errorCode == .cancelled)
  }
}
```

- [ ] **Step 5.2: Run tests to verify cancel behaviour**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild 2>&1 | grep -E "TUSUploadEngineTests|passed|failed"
```

Expected: all tests pass.

- [ ] **Step 5.3: Format and commit**

```bash
make format
git add Tests/StorageTests/TUSUploadEngineTests.swift
git commit -m "test(storage): add TUS cancel mid-upload tests"
```

---

## Task 6: Wire upload methods in `StorageFileAPI`

**Files:**
- Modify: `Sources/Storage/StorageFileAPI.swift`

- [ ] **Step 6.1: Replace `upload`, `update`, `uploadToSignedURL` signatures**

In `Sources/Storage/StorageFileAPI.swift`, replace all existing `upload`, `update`, and `uploadToSignedURL` methods (the `async throws -> FileUploadResponse` and `async throws -> SignedURLUploadResponse` variants) and the private `_uploadOrUpdate` helper with the following.

Keep `uploadMultipart`, `UploadProgressDelegate`, and all other private helpers in place — they are still used by `uploadToSignedURL`.

**Replace `_uploadOrUpdate`, `upload`, and `update`:**

```swift
@discardableResult
public func upload(
  _ path: String,
  data: Data,
  options: FileOptions = FileOptions()
) -> StorageUploadTask {
  let opts = options.contentType == nil
    ? FileOptions(
      cacheControl: options.cacheControl,
      contentType: defaultFileOptions.contentType,
      upsert: options.upsert,
      metadata: options.metadata
    ) : options
  return TUSUploadEngine.makeTask(
    bucketId: bucketId,
    path: path,
    source: .data(data),
    options: opts,
    client: client
  )
}

@discardableResult
public func upload(
  _ path: String,
  fileURL: URL,
  options: FileOptions = FileOptions()
) -> StorageUploadTask {
  TUSUploadEngine.makeTask(
    bucketId: bucketId,
    path: path,
    source: .fileURL(fileURL),
    options: options,
    client: client
  )
}

@discardableResult
public func update(
  _ path: String,
  data: Data,
  options: FileOptions = FileOptions()
) -> StorageUploadTask {
  var upsertOptions = options
  upsertOptions.upsert = true
  return TUSUploadEngine.makeTask(
    bucketId: bucketId,
    path: path,
    source: .data(data),
    options: upsertOptions,
    client: client
  )
}

@discardableResult
public func update(
  _ path: String,
  fileURL: URL,
  options: FileOptions = FileOptions()
) -> StorageUploadTask {
  var upsertOptions = options
  upsertOptions.upsert = true
  return TUSUploadEngine.makeTask(
    bucketId: bucketId,
    path: path,
    source: .fileURL(fileURL),
    options: upsertOptions,
    client: client
  )
}
```

**Replace `uploadToSignedURL` methods** (keep multipart, just wrap in task):

```swift
@discardableResult
public func uploadToSignedURL(
  _ path: String,
  token: String,
  data: Data,
  options: FileOptions = FileOptions()
) -> StorageTransferTask<SignedURLUploadResponse> {
  let (eventStream, eventsContinuation) =
    AsyncStream<TransferEvent<SignedURLUploadResponse>>.makeStream()
  let (resultStream, resultContinuation) =
    AsyncStream<Result<SignedURLUploadResponse, any Error>>.makeStream(
      bufferingPolicy: .bufferingNewest(1))

  let resultTask = Task<SignedURLUploadResponse, any Error> {
    for await r in resultStream { return try r.get() }
    throw StorageError.cancelled
  }

  let transfer = StorageTransferTask<SignedURLUploadResponse>(
    events: eventStream,
    resultTask: resultTask,
    pause: {},
    resume: {},
    cancel: {}
  )

  Task {
    do {
      let response = try await _uploadToSignedURL(path, token: token, file: .data(data), options: options)
      eventsContinuation.yield(.completed(response))
      eventsContinuation.finish()
      resultContinuation.yield(.success(response))
    } catch let error as StorageError {
      eventsContinuation.yield(.failed(error))
      eventsContinuation.finish()
      resultContinuation.yield(.failure(error))
    } catch {
      let storageError = StorageError.networkError(underlying: error)
      eventsContinuation.yield(.failed(storageError))
      eventsContinuation.finish()
      resultContinuation.yield(.failure(storageError))
    }
  }

  return transfer
}

@discardableResult
public func uploadToSignedURL(
  _ path: String,
  token: String,
  fileURL: URL,
  options: FileOptions = FileOptions()
) -> StorageTransferTask<SignedURLUploadResponse> {
  let (eventStream, eventsContinuation) =
    AsyncStream<TransferEvent<SignedURLUploadResponse>>.makeStream()
  let (resultStream, resultContinuation) =
    AsyncStream<Result<SignedURLUploadResponse, any Error>>.makeStream(
      bufferingPolicy: .bufferingNewest(1))

  let resultTask = Task<SignedURLUploadResponse, any Error> {
    for await r in resultStream { return try r.get() }
    throw StorageError.cancelled
  }

  let transfer = StorageTransferTask<SignedURLUploadResponse>(
    events: eventStream,
    resultTask: resultTask,
    pause: {},
    resume: {},
    cancel: {}
  )

  Task {
    do {
      let response = try await _uploadToSignedURL(path, token: token, file: .fileURL(fileURL), options: options)
      eventsContinuation.yield(.completed(response))
      eventsContinuation.finish()
      resultContinuation.yield(.success(response))
    } catch let error as StorageError {
      eventsContinuation.yield(.failed(error))
      eventsContinuation.finish()
      resultContinuation.yield(.failure(error))
    } catch {
      let storageError = StorageError.networkError(underlying: error)
      eventsContinuation.yield(.failed(storageError))
      eventsContinuation.finish()
      resultContinuation.yield(.failure(storageError))
    }
  }

  return transfer
}
```

Rename the existing `uploadToSignedURL` implementation to `_uploadToSignedURL` (private, keep as `async throws -> SignedURLUploadResponse`).

- [ ] **Step 6.2: Build to verify no errors**

```bash
swift build 2>&1 | grep -E "error:" | head -20
```

Fix any type errors. Common issue: `FileOptions.upsert` — check if it's a `var` (mutable) in the struct. If not, construct a new `FileOptions` with `upsert: true`.

- [ ] **Step 6.3: Run all Storage tests**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild 2>&1 | grep -E "passed|failed|error:"
```

Expected: all existing tests pass (some may need updating if they called `await bucket.upload(...)` — those call sites now need to use `try await bucket.upload(...).result`).

- [ ] **Step 6.4: Update broken test call sites in `StorageFileAPITests.swift`**

Find any test that does `try await bucket.upload(...)` or `try await bucket.update(...)` and update them to:

```swift
try await bucket.upload("path", data: data).result
try await bucket.update("path", data: data).result
```

Similarly for `uploadToSignedURL`:

```swift
try await bucket.uploadToSignedURL("path", token: token, data: data).result
```

- [ ] **Step 6.5: Run tests again to confirm all pass**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild 2>&1 | grep -E "passed|failed|error:"
```

- [ ] **Step 6.6: Format and commit**

```bash
make format
git add Sources/Storage/StorageFileAPI.swift Tests/StorageTests/StorageFileAPITests.swift
git commit -m "feat(storage): replace upload/update/uploadToSignedURL with StorageTransferTask return"
```

---

## Task 7: `DownloadSessionDelegate`

**Files:**
- Create: `Sources/Storage/DownloadSessionDelegate.swift`
- Create: `Tests/StorageTests/DownloadSessionDelegateTests.swift`

- [ ] **Step 7.1: Write failing tests for delegate routing**

Create `Tests/StorageTests/DownloadSessionDelegateTests.swift`:

```swift
import Foundation
import Testing
@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite struct DownloadSessionDelegateTests {

  @Test func routesProgressToCorrectTask() async throws {
    let delegate = DownloadSessionDelegate()
    let session = URLSession(
      configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

    let (stream1, continuation1, task1) = delegate.makeDownloadTask(in: session, request: URLRequest(url: URL(string: "https://example.com/file1")!))
    let (stream2, continuation2, task2) = delegate.makeDownloadTask(in: session, request: URLRequest(url: URL(string: "https://example.com/file2")!))

    // Simulate progress for task1 only
    delegate.urlSession(
      session, downloadTask: task1,
      didWriteData: 500, totalBytesWritten: 500, totalBytesExpectedToWrite: 1000
    )

    var task1Events: [TransferEvent<URL>] = []
    var task2Events: [TransferEvent<URL>] = []

    // Drain task2 first — should be empty since we only pushed to task1
    continuation2.finish()
    for await event in stream2 { task2Events.append(event) }

    continuation1.finish()
    for await event in stream1 { task1Events.append(event) }

    #expect(task1Events.count == 1)
    if case .progress(let p) = task1Events[0] {
      #expect(p.bytesTransferred == 500)
      #expect(p.totalBytes == 1000)
    } else {
      Issue.record("Expected .progress")
    }
    #expect(task2Events.isEmpty)
  }

  @Test func completionMovesFileAndYieldsURL() async throws {
    let delegate = DownloadSessionDelegate()
    let session = URLSession(
      configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

    let (stream, _, task) = delegate.makeDownloadTask(in: session, request: URLRequest(url: URL(string: "https://example.com/file")!))

    // Write a temp file to simulate OS-provided location
    let tmpSrc = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try Data("content".utf8).write(to: tmpSrc)

    delegate.urlSession(session, downloadTask: task, didFinishDownloadingTo: tmpSrc)

    var completedURL: URL?
    for await event in stream {
      if case .completed(let url) = event { completedURL = url }
    }
    let url = try #require(completedURL)
    #expect(FileManager.default.fileExists(atPath: url.path))
    // Source should be gone (moved, not copied)
    #expect(!FileManager.default.fileExists(atPath: tmpSrc.path))
  }

  @Test func networkErrorYieldsFailedEvent() async {
    let delegate = DownloadSessionDelegate()
    let session = URLSession(
      configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

    let (stream, _, task) = delegate.makeDownloadTask(in: session, request: URLRequest(url: URL(string: "https://example.com/file")!))

    let error = URLError(.networkConnectionLost)
    delegate.urlSession(session, task: task, didCompleteWithError: error)

    var lastEvent: TransferEvent<URL>?
    for await event in stream { lastEvent = event }

    if case .failed(let storageError) = lastEvent {
      #expect(storageError.errorCode == .networkError)
    } else {
      Issue.record("Expected .failed(.networkError)")
    }
  }
}
```

- [ ] **Step 7.2: Run tests to confirm they fail**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild 2>&1 | grep -E "DownloadSessionDelegateTests|error:"
```

Expected: compile error — `DownloadSessionDelegate` not found.

- [ ] **Step 7.3: Create `Sources/Storage/DownloadSessionDelegate.swift`**

```swift
//
//  DownloadSessionDelegate.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import ConcurrencyExtras
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

  struct DownloadTaskState {
    let eventsContinuation: AsyncStream<TransferEvent<URL>>.Continuation
    let resultContinuation: AsyncStream<Result<URL, any Error>>.Continuation
  }

  private let tasks = LockIsolated<[Int: DownloadTaskState]>([:])
  private let backgroundCompletionHandler = LockIsolated<(@Sendable () -> Void)?>(nil)

  // MARK: - Task creation

  /// Creates a new download task registered with this delegate and returns the stream,
  /// events continuation, and the underlying `URLSessionDownloadTask` (already resumed).
  func makeDownloadTask(
    in session: URLSession,
    request: URLRequest
  ) -> (
    stream: AsyncStream<TransferEvent<URL>>,
    eventsContinuation: AsyncStream<TransferEvent<URL>>.Continuation,
    task: URLSessionDownloadTask
  ) {
    let (stream, eventsContinuation) = AsyncStream<TransferEvent<URL>>.makeStream()
    let (resultStream, resultContinuation) = AsyncStream<Result<URL, any Error>>.makeStream(
      bufferingPolicy: .bufferingNewest(1))

    let urlTask = session.downloadTask(with: request)

    tasks.withValue {
      $0[urlTask.taskIdentifier] = DownloadTaskState(
        eventsContinuation: eventsContinuation,
        resultContinuation: resultContinuation
      )
    }

    urlTask.resume()
    return (stream, eventsContinuation, urlTask)
  }

  /// Creates a `StorageDownloadTask` handle backed by this delegate.
  func makeStorageDownloadTask(in session: URLSession, request: URLRequest) -> StorageDownloadTask {
    let (eventStream, _, urlTask) = makeDownloadTask(in: session, request: request)

    let (resultStream, _) = resultStreamForTask(urlTask.taskIdentifier)

    let resultTask = Task<URL, any Error> {
      for await r in resultStream { return try r.get() }
      throw StorageError.cancelled
    }

    return StorageDownloadTask(
      events: eventStream,
      resultTask: resultTask,
      pause: { urlTask.suspend() },
      resume: { urlTask.resume() },
      cancel: { urlTask.cancel() }
    )
  }

  func setBackgroundCompletionHandler(_ handler: @escaping @Sendable () -> Void) {
    backgroundCompletionHandler.setValue(handler)
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard let state = tasks.value[downloadTask.taskIdentifier] else { return }
    state.eventsContinuation.yield(
      .progress(
        TransferProgress(
          bytesTransferred: totalBytesWritten,
          totalBytes: totalBytesExpectedToWrite
        )))
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let state = tasks.value[downloadTask.taskIdentifier] else { return }

    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    do {
      try FileManager.default.moveItem(at: location, to: destination)
      state.eventsContinuation.yield(.completed(destination))
      state.eventsContinuation.finish()
      state.resultContinuation.yield(.success(destination))
    } catch {
      let storageError = StorageError.fileSystemError(underlying: error)
      state.eventsContinuation.yield(.failed(storageError))
      state.eventsContinuation.finish()
      state.resultContinuation.yield(.failure(storageError))
    }

    tasks.withValue { $0.removeValue(forKey: downloadTask.taskIdentifier) }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    guard let error else { return }
    guard let state = tasks.value[task.taskIdentifier] else { return }

    let storageError: StorageError
    if (error as? URLError)?.code == .cancelled {
      storageError = .cancelled
    } else {
      storageError = .networkError(underlying: error)
    }

    state.eventsContinuation.yield(.failed(storageError))
    state.eventsContinuation.finish()
    state.resultContinuation.yield(.failure(storageError))
    tasks.withValue { $0.removeValue(forKey: task.taskIdentifier) }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    backgroundCompletionHandler.value?()
    backgroundCompletionHandler.setValue(nil)
  }

  // MARK: - Private

  private func resultStreamForTask(_ taskIdentifier: Int) -> (
    AsyncStream<Result<URL, any Error>>, AsyncStream<Result<URL, any Error>>.Continuation
  ) {
    // This is only called immediately after makeDownloadTask — the state always exists.
    fatalError("resultStreamForTask called for unknown task \(taskIdentifier)")
  }
}
```

Wait — there's a design issue. `makeStorageDownloadTask` needs access to the `resultStream` but the current `makeDownloadTask` only returns the event stream. Let me restructure.

Replace the above `makeDownloadTask` and `makeStorageDownloadTask` with a single method:

```swift
/// Creates a `StorageDownloadTask` backed by this delegate for the given request.
/// The underlying `URLSessionDownloadTask` is resumed immediately.
func makeStorageDownloadTask(in session: URLSession, request: URLRequest) -> StorageDownloadTask {
  let (eventStream, eventsContinuation) = AsyncStream<TransferEvent<URL>>.makeStream()
  let (resultStream, resultContinuation) = AsyncStream<Result<URL, any Error>>.makeStream(
    bufferingPolicy: .bufferingNewest(1))

  let urlTask = session.downloadTask(with: request)

  tasks.withValue {
    $0[urlTask.taskIdentifier] = DownloadTaskState(
      eventsContinuation: eventsContinuation,
      resultContinuation: resultContinuation
    )
  }

  let resultTask = Task<URL, any Error> {
    for await r in resultStream { return try r.get() }
    throw StorageError.cancelled
  }

  let storageTask = StorageDownloadTask(
    events: eventStream,
    resultTask: resultTask,
    pause: { urlTask.suspend() },
    resume: { urlTask.resume() },
    cancel: { urlTask.cancel() }
  )

  urlTask.resume()
  return storageTask
}
```

And for tests, expose a `makeDownloadTask` with `package` access (same module as the tests via `@testable import`):

```swift
// Used by unit tests to drive delegate callbacks directly.
package func makeDownloadTask(
  in session: URLSession,
  request: URLRequest
) -> (
  stream: AsyncStream<TransferEvent<URL>>,
  eventsContinuation: AsyncStream<TransferEvent<URL>>.Continuation,
  task: URLSessionDownloadTask
) {
  let (eventStream, eventsContinuation) = AsyncStream<TransferEvent<URL>>.makeStream()
  let (resultStream, resultContinuation) = AsyncStream<Result<URL, any Error>>.makeStream(
    bufferingPolicy: .bufferingNewest(1))
  let urlTask = session.downloadTask(with: request)
  tasks.withValue {
    $0[urlTask.taskIdentifier] = DownloadTaskState(
      eventsContinuation: eventsContinuation,
      resultContinuation: resultContinuation
    )
  }
  return (eventStream, eventsContinuation, urlTask)
}
```

Place the final `DownloadSessionDelegate.swift` with the above changes.

- [ ] **Step 7.4: Run tests to confirm they pass**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild 2>&1 | grep -E "DownloadSessionDelegateTests|passed|failed"
```

Expected: all three delegate tests pass.

- [ ] **Step 7.5: Format and commit**

```bash
make format
git add Sources/Storage/DownloadSessionDelegate.swift Tests/StorageTests/DownloadSessionDelegateTests.swift
git commit -m "feat(storage): add DownloadSessionDelegate with URLSession background support"
```

---

## Task 8: Wire download methods + `downloadData`

**Files:**
- Modify: `Sources/Storage/StorageFileAPI.swift`
- Modify: `Sources/Storage/StorageClient.swift` (verify `handleBackgroundEvents` and session setup from Task 2 compile with the delegate now existing)

- [ ] **Step 8.1: Replace `download` and add `downloadData` in `StorageFileAPI`**

In `Sources/Storage/StorageFileAPI.swift`, replace the existing `download` method (which returns `async throws -> Data`) with:

```swift
/// Downloads a file to a temporary location on disk.
///
/// The `completed` event delivers a `URL` pointing to a temporary file. **Move the file
/// before the next app launch** — it is not guaranteed to persist.
///
/// When ``StorageClientConfiguration/backgroundDownloadSessionIdentifier`` is set, the
/// transfer continues while the app is suspended. Wire up
/// ``StorageClient/handleBackgroundEvents(forSessionIdentifier:completionHandler:)`` in
/// your `AppDelegate`.
///
/// - Parameters:
///   - path: The path within the bucket, e.g. `"folder/image.png"`.
///   - options: Optional image transform parameters.
/// - Returns: A ``StorageDownloadTask`` whose `.completed` value is a `URL` to the file on disk.
@discardableResult
public func download(
  path: String,
  options: TransformOptions? = nil
) -> StorageDownloadTask {
  var request = URLRequest(
    url: _downloadURL(path: path, options: options))
  for (key, value) in client.mergedHeaders([:]) {
    request.setValue(value, forHTTPHeaderField: key)
  }
  return client.downloadDelegate.makeStorageDownloadTask(
    in: client.downloadSession,
    request: request
  )
}

/// Downloads a file into memory and returns the raw bytes.
///
/// Not background-capable — use ``download(path:options:)`` for large files or background transfers.
///
/// - Parameters:
///   - path: The path within the bucket.
///   - options: Optional image transform parameters.
/// - Returns: A ``StorageTransferTask`` whose `.completed` value is the file `Data`.
@discardableResult
public func downloadData(
  path: String,
  options: TransformOptions? = nil
) -> StorageTransferTask<Data> {
  download(path: path, options: options).mapResult { url in
    let data = try Data(contentsOf: url)
    try? FileManager.default.removeItem(at: url)
    return data
  }
}
```

Also add the private helper (or reuse existing `_getDownloadURL`-style logic):

```swift
private func _downloadURL(path: String, options: TransformOptions?) -> URL {
  let cleanPath = _removeEmptyFolders(path)
  let finalPath = _getFinalPath(cleanPath)

  if let options, !options.isEmpty {
    return client.url
      .appendingPathComponent("render/image/authenticated/\(finalPath)")
      .appending(queryItems: options.queryItems)
  }
  return client.url.appendingPathComponent("object/authenticated/\(finalPath)")
}
```

Check whether the existing `download` method already has this URL-construction logic — if so, extract it into `_downloadURL` and reuse.

- [ ] **Step 8.2: Build to verify no errors**

```bash
swift build 2>&1 | grep -E "error:" | head -20
```

- [ ] **Step 8.3: Update existing `download` tests in `StorageFileAPITests.swift`**

Find tests that call `try await bucket.download(path:)` and update to:

```swift
let url = try await bucket.download(path: "file.txt").result
let data = try Data(contentsOf: url)

// Or use downloadData:
let data = try await bucket.downloadData(path: "file.txt").result
```

- [ ] **Step 8.4: Run all tests**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild 2>&1 | grep -E "passed|failed|error:"
```

Expected: all tests pass.

- [ ] **Step 8.5: Format and commit**

```bash
make format
git add Sources/Storage/StorageFileAPI.swift
git commit -m "feat(storage): replace download with StorageDownloadTask; add downloadData convenience"
```

---

## Task 9: Integration tests

**Files:**
- Create: `Tests/IntegrationTests/StorageTransferIntegrationTests.swift`

> **Note:** Integration tests require a running local Supabase instance (`supabase start` in `Tests/IntegrationTests/`). Skip this task if no local instance is available.

- [ ] **Step 9.1: Create integration test file**

Create `Tests/IntegrationTests/StorageTransferIntegrationTests.swift`:

```swift
import Foundation
import Testing
@testable import Storage

// Requires: supabase start && supabase db reset (from Tests/IntegrationTests/)

@Suite(.serialized) struct StorageTransferIntegrationTests {
  let storage = StorageClient(
    url: URL(string: "http://127.0.0.1:54321/storage/v1")!,
    configuration: StorageClientConfiguration(
      headers: [
        "Authorization": "Bearer \(ProcessInfo.processInfo.environment["SERVICE_ROLE_KEY"] ?? "")",
        "Apikey": ProcessInfo.processInfo.environment["ANON_KEY"] ?? "",
      ]
    )
  )

  let bucket = "test-transfers"

  @Test func tusUploadCompletesAndFileExists() async throws {
    let data = Data(repeating: 0xAB, count: 1 * 1024 * 1024)  // 1 MB
    let path = "integration/\(UUID().uuidString).bin"

    let response = try await storage.from(bucket).upload(path, data: data).result
    #expect(response.path == path)

    let downloaded = try await storage.from(bucket).downloadData(path: path).result
    #expect(downloaded == data)

    try await storage.from(bucket).remove(paths: [path])
  }

  @Test func tusUploadLargeFileInChunks() async throws {
    let data = Data(repeating: 0xCD, count: 13 * 1024 * 1024)  // 13 MB → 3 chunks
    let path = "integration/large-\(UUID().uuidString).bin"

    var progressValues: [Double] = []
    let task = storage.from(bucket).upload(path, data: data)

    for await event in task.events {
      if case .progress(let p) = event {
        progressValues.append(p.fractionCompleted)
      }
    }

    #expect(progressValues.count >= 2)
    #expect(progressValues.last == 1.0)

    try await storage.from(bucket).remove(paths: [path])
  }

  @Test func downloadDataMatchesUploadedContent() async throws {
    let original = Data("hello integration test".utf8)
    let path = "integration/\(UUID().uuidString).txt"

    _ = try await storage.from(bucket).upload(path, data: original, options: FileOptions(contentType: "text/plain")).result
    let downloaded = try await storage.from(bucket).downloadData(path: path).result

    #expect(downloaded == original)
    try await storage.from(bucket).remove(paths: [path])
  }

  @Test func cancelledUploadDoesNotCreateObject() async throws {
    let data = Data(repeating: 0x01, count: 13 * 1024 * 1024)
    let path = "integration/cancel-\(UUID().uuidString).bin"

    let task = storage.from(bucket).upload(path, data: data)

    Task {
      try? await Task.sleep(for: .milliseconds(200))
      task.cancel()
    }

    do {
      _ = try await task.result
    } catch let error as StorageError {
      #expect(error.errorCode == .cancelled)
    }

    // Object should not exist
    let exists = try await storage.from(bucket).exists(path: path)
    #expect(!exists)
  }
}
```

- [ ] **Step 9.2: Run integration tests**

```bash
cd Tests/IntegrationTests && supabase start && supabase db reset && cd ../..
make test-integration 2>&1 | grep -E "StorageTransferIntegrationTests|passed|failed"
```

- [ ] **Step 9.3: Format and commit**

```bash
make format
git add Tests/IntegrationTests/StorageTransferIntegrationTests.swift
git commit -m "test(storage): add TUS upload and download integration tests"
```

---

## Final verification

- [ ] **Run the full test suite one last time**

```bash
make PLATFORM=IOS XCODEBUILD_ARGUMENT=test xcodebuild 2>&1 | tail -5
```

Expected: all tests pass, no regressions.

- [ ] **Check for any remaining `async throws -> Data` or `async throws -> FileUploadResponse` signatures on public methods**

```bash
grep -n "async throws -> FileUploadResponse\|async throws -> Data\|async throws -> SignedURLUploadResponse" Sources/Storage/StorageFileAPI.swift
```

Expected: no matches (all replaced by task-returning signatures).
