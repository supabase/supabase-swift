# Storage Upload API Design

**Goal:** Expose standard multipart uploads, TUS resumable uploads, and a smart default that picks the right engine based on file size — all through a uniform `StorageUploadTask`-returning API.

**Architecture:** Two upload engines (`MultipartUploadEngine`, `TUSUploadEngine`) sit behind a shared `UploadSource` abstraction. `StorageFileAPI` exposes three method families (`upload`, `uploadMultipart`, `uploadResumable`) plus matching `update` variants. The smart default reads source size and dispatches to the right engine. All 12 methods return `StorageUploadTask`.

**Tech Stack:** Swift 6, `async/await`, `actor`, `URLSession` delegate-based progress, existing `StorageTransferTask` / `AsyncStream` plumbing.

---

## API Surface

### Upload (create, `upsert: false`)

```swift
// Smart default — ≤ 6 MB → multipart, > 6 MB → TUS
func upload(_ path: String, data: Data, options: FileOptions = .init()) -> StorageUploadTask
func upload(_ path: String, fileURL: URL, options: FileOptions = .init()) -> StorageUploadTask

// Always standard multipart
func uploadMultipart(_ path: String, data: Data, options: FileOptions = .init()) -> StorageUploadTask
func uploadMultipart(_ path: String, fileURL: URL, options: FileOptions = .init()) -> StorageUploadTask

// Always TUS / resumable
func uploadResumable(_ path: String, data: Data, options: FileOptions = .init()) -> StorageUploadTask
func uploadResumable(_ path: String, fileURL: URL, options: FileOptions = .init()) -> StorageUploadTask
```

### Update (replace, `upsert: true`)

```swift
// Smart default
func update(_ path: String, data: Data, options: FileOptions = .init()) -> StorageUploadTask
func update(_ path: String, fileURL: URL, options: FileOptions = .init()) -> StorageUploadTask

// Always standard multipart
func updateMultipart(_ path: String, data: Data, options: FileOptions = .init()) -> StorageUploadTask
func updateMultipart(_ path: String, fileURL: URL, options: FileOptions = .init()) -> StorageUploadTask

// Always TUS / resumable
func updateResumable(_ path: String, data: Data, options: FileOptions = .init()) -> StorageUploadTask
func updateResumable(_ path: String, fileURL: URL, options: FileOptions = .init()) -> StorageUploadTask
```

---

## Smart Branching Logic

The smart `upload()` / `update()` methods determine source size before choosing an engine:

- `data:` variant — `data.count`
- `fileURL:` variant — `FileManager.default.attributesOfItem(atPath:)[.size]`

```
size ≤ tusChunkSize.value (6 MB)  →  MultipartUploadEngine
size  > tusChunkSize.value         →  TUSUploadEngine
file size unreadable               →  TUSUploadEngine  (safe fallback)
```

The threshold reuses the existing package-level `tusChunkSize: LockIsolated<Int>` constant from `TUSUploadEngine.swift`, keeping the multipart/TUS boundary in sync with the TUS chunk size.

---

## MultipartUploadEngine

A new `actor MultipartUploadEngine` in `Sources/Storage/MultipartUploadEngine.swift`.

### Responsibilities

1. Build the multipart/form-data request body using the existing `FileUpload` + `MultipartBuilder` infrastructure already present in `StorageFileAPI.swift`.
2. POST to `/object/{bucketId}/{path}` (with `x-upsert: true` for update variants).
3. Memory strategy — mirrors the existing private `uploadMultipart` behaviour:
   - `FileUpload.data(_)` sources and `FileUpload.url(_)` sources **< 10 MB**: build body in memory via `MultipartBuilder.buildInMemory()`, upload via `session.uploadTask(with:from:delegate:)`
   - `FileUpload.url(_)` sources **≥ 10 MB**: write multipart body to a temp file via `MultipartBuilder.buildToTempFile()`, upload via `session.uploadTask(with:fromFile:delegate:)`, delete temp file in `defer`
   - This threshold is the existing `FileUpload.usesTempFileUpload` computed property (≥ 10 MB).
4. Pass a `URLSessionTaskDelegate` to the upload task. Its `urlSession(_:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)` method yields `.progress(TransferProgress(bytesTransferred:totalBytes:))` events into the events continuation.
5. On success, decode `FileUploadResponse` from the response body and yield `.completed(response)`; on error, yield `.failed(StorageError)`.
6. `cancel()` cancels the underlying `URLSessionUploadTask` and finishes both continuations with a `.cancelled` error.
7. `pause()` and `resume()` are no-ops — multipart is a single HTTP request.

### State

```swift
enum State {
  case idle
  case uploading(task: URLSessionUploadTask)
  case completed(FileUploadResponse)
  case failed(StorageError)
  case cancelled
}
```

### Factory

`MultipartUploadEngine.makeTask(bucketId:path:file:options:client:) -> StorageUploadTask` — wires up `AsyncStream` continuations and returns a `StorageUploadTask`. Takes a `FileUpload` (not `UploadSource`) as the source parameter, matching the existing multipart infrastructure.

---

## Internal Source Representations

The two engines use different internal source types — no sharing required:

- `TUSUploadEngine` keeps `UploadSource` (defined in `TUSUploadEngine.swift`) — designed for chunked reading.
- `MultipartUploadEngine` takes a `FileUpload` — the existing abstraction used by `MultipartBuilder`.

The smart default checks source size directly before dispatching, without a shared abstraction:

```swift
// data variant
let size = data.count

// fileURL variant
let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
```

---

## StorageFileAPI Changes

### New methods

Add `uploadMultipart`, `uploadResumable`, `updateMultipart`, `updateResumable` alongside the existing (renamed-to-smart-default) `upload` and `update`.

### Smart default implementation sketch

```swift
public func upload(_ path: String, data: Data, options: FileOptions = .init()) -> StorageUploadTask {
    let source = UploadSource.data(data)
    let size = data.count
    if size <= tusChunkSize.value {
        return MultipartUploadEngine.makeTask(bucketId: bucketId, path: path,
                                              source: source, options: options, client: client)
    } else {
        return TUSUploadEngine.makeTask(bucketId: bucketId, path: path,
                                        source: source, options: options, client: client)
    }
}

public func upload(_ path: String, fileURL: URL, options: FileOptions = .init()) -> StorageUploadTask {
    let source = UploadSource.fileURL(fileURL)
    let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? Int.max
    if size <= tusChunkSize.value {
        return MultipartUploadEngine.makeTask(bucketId: bucketId, path: path,
                                              source: source, options: options, client: client)
    } else {
        return TUSUploadEngine.makeTask(bucketId: bucketId, path: path,
                                        source: source, options: options, client: client)
    }
}
```

The `update` variants are identical except `options.upsert` is forced to `true`.

---

## File Structure

| Action | File |
|--------|------|
| Create | `Sources/Storage/MultipartUploadEngine.swift` |
| Modify | `Sources/Storage/StorageFileAPI.swift` — add 8 new methods (`uploadMultipart`, `uploadResumable`, `updateMultipart`, `updateResumable` × 2 variants each), keep existing `upload`/`update` as smart defaults; `FileUpload` and `MultipartBuilder` usage moves from the private `uploadMultipart` method into `MultipartUploadEngine` |
| No change | `Sources/Storage/TUSUploadEngine.swift` — `UploadSource` stays here |

---

## Testing

### Unit tests (`Tests/StorageTests/`)

- `MultipartUploadEngineTests.swift` — mock HTTP session; assert multipart body structure, progress events fire, completion delivers `FileUploadResponse`, cancel stops the task
- `StorageFileAPITests.swift` — add tests for each of the 12 new methods; assert correct engine is chosen in smart default (mock responses for both paths), `uploadMultipart` / `uploadResumable` call the right engine regardless of size

### Integration tests (`Tests/IntegrationTests/`)

- Add `multipartUploadCompletesAndFileExists` — upload ≤ 6 MB via `uploadMultipart`, download and verify bytes match
- Add `smartDefaultUsesMultipartForSmallFile` — upload 1 KB via `upload()`, verify it completes (can't observe engine selection directly, but success confirms the path)
- Add `smartDefaultUsesTUSForLargeFile` — upload 13 MB via `upload()`, verify it completes in chunks
