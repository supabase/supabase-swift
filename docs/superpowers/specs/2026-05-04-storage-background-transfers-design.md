# Storage Background Transfers Design

**Date:** 2026-05-04  
**Status:** Approved  
**Scope:** `Sources/Storage` — uploads (TUS resumable protocol) and downloads (background `URLSession`)

---

## Goals

- First-party support for resumable uploads (TUS 1.0.0) and background downloads in the Supabase Swift Storage SDK.
- Idiomatic Swift 6 API: `AsyncSequence`-based progress, structured concurrency, `Sendable`-safe.
- A unified `StorageTransferTask<Success>` handle that works for both directions.
- Tasks start immediately and are `@discardableResult` — fire-and-forget works without any extra calls.
- Breaking changes to existing `upload` / `download` signatures are accepted.

---

## Out of Scope (v1)

- Cross-launch transfer resumption (app killed mid-transfer; OS continues the download, but re-attaching to it on relaunch is deferred).
- Sub-chunk byte-level upload progress (chunk-level is sufficient).
- TUS for signed-URL uploads (pre-signed endpoint does not support TUS; those stay multipart).

---

## Architecture Overview

Two internal engines, one public task type:

```
StorageFileAPI
├── TUSUploadEngine (actor)         — all upload methods
│   ├── POST  → create upload (get Location)
│   ├── PATCH → send chunks (6 MB minimum)
│   └── HEAD  → re-sync offset on resume
└── DownloadSessionDelegate (class) — all download methods
    ├── URLSession (default or background)
    └── routing table: taskIdentifier → DownloadTaskState
```

Both engines feed their output into:
- `AsyncStream<TransferEvent<Success>>.Continuation` (`.events` property)
- `CheckedContinuation<Success, any Error>` (`.result` property)

These are independent — consuming one does not affect the other.

---

## Section 1: Public API

### `StorageTransferTask<Success>`

```swift
public final class StorageTransferTask<Success: Sendable>: Sendable {

    /// Stream of progress and terminal events. Can be iterated independently
    /// of `result`. The stream finishes after `.completed` or `.failed`.
    public let events: AsyncStream<TransferEvent<Success>>

    /// Awaits the final result. Throws `StorageError.cancelled` if cancelled,
    /// or `StorageError` for any transfer failure. Independent of `events`.
    /// Safe to await from multiple concurrent callers — backed by an internal
    /// `Task<Success, any Error>` whose `.value` is multi-cast-safe.
    public var result: Success { get async throws }

    /// Suspends the transfer. For uploads: finishes the current in-flight chunk
    /// before suspending. For downloads: suspends the URLSessionTask.
    public func pause()

    /// Resumes a paused transfer. For uploads: HEADs the upload URL to confirm
    /// server offset before restarting PATCH loop.
    public func resume()

    /// Cancels the transfer immediately. Yields `.failed(.cancelled)` and
    /// finishes the stream.
    public func cancel()
}

public enum TransferEvent<Success: Sendable>: Sendable {
    case progress(TransferProgress)
    case completed(Success)
    case failed(StorageError)   // stream ends after this case
}

public struct TransferProgress: Sendable {
    public let bytesTransferred: Int64
    public let totalBytes: Int64
    public var fractionCompleted: Double { Double(bytesTransferred) / Double(totalBytes) }
}

public typealias StorageUploadTask   = StorageTransferTask<FileUploadResponse>
public typealias StorageDownloadTask = StorageTransferTask<URL>
```

---

### `StorageFileAPI` method signatures (breaking changes)

```swift
// --- Uploads (TUS-backed) ---

@discardableResult
public func upload(
    _ path: String,
    data: Data,
    options: FileOptions = FileOptions()
) -> StorageUploadTask

@discardableResult
public func upload(
    _ path: String,
    fileURL: URL,
    options: FileOptions = FileOptions()
) -> StorageUploadTask

@discardableResult
public func update(
    _ path: String,
    data: Data,
    options: FileOptions = FileOptions()
) -> StorageUploadTask

@discardableResult
public func update(
    _ path: String,
    fileURL: URL,
    options: FileOptions = FileOptions()
) -> StorageUploadTask

// Signed-URL uploads: multipart (TUS not applicable to pre-signed endpoints)
@discardableResult
public func uploadToSignedURL(
    _ path: String,
    token: String,
    data: Data,
    options: FileOptions = FileOptions()
) -> StorageTransferTask<SignedURLUploadResponse>

@discardableResult
public func uploadToSignedURL(
    _ path: String,
    token: String,
    fileURL: URL,
    options: FileOptions = FileOptions()
) -> StorageTransferTask<SignedURLUploadResponse>

// --- Downloads ---

/// Background-capable. Delivers a URL to a file on disk (caller should move
/// before it is cleaned up). Use a background session identifier in
/// StorageClientConfiguration for OS-managed background transfers.
@discardableResult
public func download(
    path: String,
    options: TransformOptions? = nil
) -> StorageDownloadTask

/// Foreground convenience. Downloads into memory; not background-capable.
@discardableResult
public func downloadData(
    path: String,
    options: TransformOptions? = nil
) -> StorageTransferTask<Data>
```

---

### Call-site examples

```swift
// Fire and forget
storage.from("avatars").upload("profile.jpg", fileURL: photoURL)

// Progress bar
let task = storage.from("videos").upload("movie.mp4", fileURL: videoURL)
for await event in task.events {
    switch event {
    case .progress(let p):   progressBar.progress = p.fractionCompleted
    case .completed(let r):  print("Uploaded to \(r.fullPath)")
    case .failed(let error): showError(error)
    }
}

// Await result directly
let response = try await storage.from("avatars")
    .upload("profile.jpg", fileURL: photoURL)
    .result

// Background download (survives app suspension with background session configured)
let task = storage.from("assets").download(path: "manual.pdf")
for await event in task.events {
    switch event {
    case .progress(let p):     updateUI(p)
    case .completed(let url):  try FileManager.default.moveItem(at: url, to: destination)
    case .failed(let error):   handleError(error)
    }
}

// In-memory download
let data = try await storage.from("thumbnails").downloadData(path: "thumb.png").result

// Pause / resume
task.pause()
task.resume()

// Swift Task cancellation propagates
let swiftTask = Task {
    for await event in task.events { ... }
}
swiftTask.cancel()  // cancels the underlying transfer
```

---

## Section 2: TUS Upload Engine

### Protocol (Supabase flavour, TUS 1.0.0)

```
POST  /storage/v1/upload/resumable
      Tus-Resumable: 1.0.0
      Upload-Length: <total bytes>
      Upload-Metadata: bucketName <b64>, objectName <b64>,
                       contentType <b64>, cacheControl <b64>
← 201 Location: <upload-url>

PATCH <upload-url>                          (repeat, 6 MB chunks minimum)
      Tus-Resumable: 1.0.0
      Content-Type: application/offset+octet-stream
      Upload-Offset: <current offset>
      Body: <chunk bytes>
← 204 Upload-Offset: <new offset>

HEAD  <upload-url>                          (on resume)
      Tus-Resumable: 1.0.0
← 200 Upload-Offset: <bytes received so far>
```

Upload is complete when `Upload-Offset == Upload-Length`. Supabase returns `FileUploadResponse` in the final PATCH response body.

### `TUSUploadEngine` (actor)

```swift
actor TUSUploadEngine {
    enum State {
        case idle
        case creating                              // POST in flight
        case uploading(uploadURL: URL, offset: Int64)
        case paused(uploadURL: URL, offset: Int64)
        case completed(FileUploadResponse)
        case failed(StorageError)
        case cancelled
    }

    enum UploadSource {
        case data(Data)      // sliced per chunk, never fully copied
        case fileURL(URL)    // FileHandle.read(upToCount:) per chunk
    }
}
```

State transitions:

```
idle → creating → uploading ⇄ paused → completed
          any state → cancelled / failed
```

### Chunk size

6 MB (`6 * 1024 * 1024` bytes) — Supabase's minimum for S3 multipart compatibility.

### Progress granularity

One `.progress` event per completed PATCH, using cumulative `Upload-Offset` as `bytesTransferred`. Sub-chunk byte-level progress is not wired in v1.

### Pause / resume / cancel behaviour

| Action | Effect |
|---|---|
| `pause()` | Finishes the current in-flight PATCH, then suspends. Offset preserved in state. |
| `resume()` | `HEAD` upload URL to confirm server offset, restart PATCH loop from confirmed offset. |
| `cancel()` | `URLSessionTask.cancel()` on current PATCH, transition to `.cancelled`. |
| Swift `Task` cancellation | `Task.checkCancellation()` checked between chunks; flows into `cancel()`. |
| `AsyncStream` consumer exits | `onTermination` closure fires → `engine.cancel()`. |

### Engine lifetime

Each call to `upload()` / `update()` creates a new `TUSUploadEngine` instance owned by the returned `StorageTransferTask`. There is no shared engine or upload queue — engines are independent and concurrent uploads run in parallel.

### `update` vs `upload`

`update` sets `FileOptions.upsert = true` then delegates to the same TUS engine path. No separate engine needed.

---

## Section 3: Background Download Engine

### Session configuration

Background download support is opt-in via `StorageClientConfiguration`:

```swift
public struct StorageClientConfiguration {
    // ... existing fields ...

    /// When set, downloads use URLSessionConfiguration.background(withIdentifier:),
    /// enabling OS-managed transfers that survive app suspension.
    /// When nil, a default URLSession is used.
    public var backgroundDownloadSessionIdentifier: String?
}
```

At `StorageClient` init:

```swift
let sessionConfig: URLSessionConfiguration = backgroundIdentifier.map {
    .background(withIdentifier: $0)
} ?? .default

let downloadSession = URLSession(
    configuration: sessionConfig,
    delegate: downloadDelegate,   // DownloadSessionDelegate instance on StorageFileAPI
    delegateQueue: nil
)
```

### `DownloadSessionDelegate` routing table

Background sessions prohibit task-specific delegates, so a single shared delegate routes by `taskIdentifier`:

```swift
final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    struct DownloadTaskState {
        let eventsContinuation: AsyncStream<TransferEvent<URL>>.Continuation
        let resultContinuation: CheckedContinuation<URL, any Error>
    }

    private let tasks = LockIsolated<[Int: DownloadTaskState]>([:])
}
```

Three delegate callbacks handle all routing:

- `didWriteData` → yields `.progress`
- `didFinishDownloadingTo` → moves temp file to stable temp path, yields `.completed`, finishes stream, resumes result continuation
- `didCompleteWithError` → yields `.failed`, finishes stream, throws on result continuation

### File destination

The delegate moves the OS-provided temp file to `FileManager.default.temporaryDirectory/<UUID>` inside `didFinishDownloadingTo` (must happen before the delegate returns). The caller receives this URL and is responsible for moving it to a permanent location.

### App integration (background wakeup)

```swift
// StorageClient
public func handleBackgroundEvents(
    forSessionIdentifier identifier: String,
    completionHandler: @escaping @Sendable () -> Void
)
```

The stored `completionHandler` is invoked inside `urlSessionDidFinishEvents(forBackgroundURLSession:)`.

**One-time app setup:**

```swift
// AppDelegate / SceneDelegate
func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
) {
    supabase.storage.handleBackgroundEvents(
        forSessionIdentifier: identifier,
        completionHandler: completionHandler
    )
}
```

### `downloadData` implementation

`downloadData` wraps `download` via an internal `mapResult` helper that transforms the success type:

```swift
public func downloadData(path: String, options: TransformOptions? = nil) -> StorageTransferTask<Data> {
    download(path: path, options: options).mapResult { url in
        let data = try Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        return data
    }
}
```

`mapResult` re-emits progress events unchanged and maps only `.completed`.

### Foreground vs background comparison

| | `download` (no background ID) | `download` (background ID set) | `downloadData` |
|---|---|---|---|
| Session | `.default` | `.background(identifier)` | `.default` |
| Result | `URL` (temp file) | `URL` (temp file, must move) | `Data` |
| Survives app suspension | No | Yes | No |
| Progress events | Yes | Yes | Yes |
| `handleBackgroundEvents` needed | No | Yes | No |

---

## Section 4: Error Handling & Cancellation

### `StorageError` additions

Three new cases:

```swift
public enum StorageError: Error {
    // ... existing cases ...
    case networkError(underlying: any Error)      // transient network failure (retriable)
    case fileSystemError(underlying: any Error)   // file move or read failure
    case cancelled                                 // explicit cancel or Task cancellation
}
```

### Error mapping table

| Source | Condition | Maps to |
|---|---|---|
| TUS POST | 4xx/5xx | `.serverError(message:statusCode:error:)` |
| TUS PATCH | network drop | `.networkError` (retriable on resume) |
| TUS PATCH | 409 Conflict | HEAD to re-sync offset → silent retry |
| TUS PATCH | 423 Locked | `.serverError` |
| Download | network drop | `.networkError` |
| Download | 4xx/5xx | `.serverError` |
| Download | file move fails | `.fileSystemError(underlying:)` |
| Any | Swift Task / explicit cancel | `.cancelled` |

### Cancellation propagation paths

1. **`task.cancel()`** — direct call; transitions engine to `.cancelled` state immediately.
2. **Swift `Task` cancellation** — `Task.checkCancellation()` inside TUS chunk loop; `URLSessionTask.cancel()` via `onTermination` on the download stream.
3. **`for await` consumer exits** — `AsyncStream.Continuation.onTermination` fires → `engine.cancel()`.

---

## Section 5: Testing

### Unit tests (new file: `StorageTransferTests.swift`)

| Scenario | Method |
|---|---|
| TUS state machine transitions | Drive `TUSUploadEngine` with a mock `_HTTPClient`; assert state at each step |
| Correct chunk count and offsets | Feed 18 MB `Data`; assert 3 PATCH requests with correct `Upload-Offset` headers |
| Resume after pause | Mock HEAD returning offset=6 MB; assert chunking restarts from chunk 2 |
| 409 Conflict triggers offset re-sync | Mock first PATCH returning 409; assert HEAD called, retry succeeds |
| Cancel mid-upload | Cancel at chunk 2; assert `.cancelled` event, no further requests |
| `DownloadSessionDelegate` routing | Two tasks in parallel; simulate delegate callbacks; assert events to correct stream |
| `result` and `events` independence | Consume both; assert neither blocks the other |
| `mapResult` transformation | Unit test in isolation with a mock task |
| `downloadData` cleans up temp file | Assert temp URL removed after stream completes |

Uses `Mocker` for HTTP mocking and `withMainSerialExecutor` from `swift-concurrency-extras` for deterministic async behaviour.

### Integration tests (added to `IntegrationTests` target)

- Upload a 20 MB file via TUS; assert server content matches
- Pause at chunk 2, resume; assert upload completes correctly
- Cancel at chunk 2; assert object not present on server
- Download a file; assert bytes match
- `downloadData`; assert `Data` matches file content

### Explicitly out of scope for tests

- True OS background suspension (requires device + `XCUITest`)
- Cross-launch resumption (deferred to v2)
