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

A new `actor MultipartUploadEngine` in `Sources/Storage/MultipartUploadEngine.swift`, structured parallel to `TUSUploadEngine`.

### Responsibilities

1. Build a `multipart/form-data` request body with a random `boundary`:
   - One part: field name `""`  (or the filename), `Content-Disposition: form-data; name=""; filename="{filename}"`, `Content-Type: {contentType}`, body = file bytes
2. POST to `/object/{bucketId}/{path}` (or `/object/{bucketId}/{path}` with `x-upsert: true` for updates)
3. Use `URLSession.uploadTask(with:from:completionHandler:)` **or** a streaming upload task with a `URLSessionTaskDelegate` for progress reporting
4. The delegate method `urlSession(_:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)` yields `.progress(TransferProgress(bytesTransferred:totalBytes:))` events into the events continuation
5. On success, decode `FileUploadResponse` from the response body and yield `.completed(response)`; on error, yield `.failed(error)`
6. `cancel()` cancels the underlying `URLSessionTask` and finishes both continuations with `.cancelled`
7. `pause()` and `resume()` are no-ops (multipart is a single HTTP request; cancellation is the only interruption)
8. The full source is loaded into memory before the request is sent (`Data(contentsOf:)` for `fileURL` variant). This is acceptable because multipart only fires for files ≤ 6 MB.

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

`MultipartUploadEngine.makeTask(bucketId:path:source:options:client:) -> StorageUploadTask` — mirrors `TUSUploadEngine.makeTask`, wires up `AsyncStream` continuations, returns a `StorageUploadTask`.

---

## UploadSource Extraction

`UploadSource` (currently defined inside `TUSUploadEngine.swift`) is moved to its own file `Sources/Storage/UploadSource.swift` so both `TUSUploadEngine` and `MultipartUploadEngine` can use it without cross-file internal access issues.

No changes to `UploadSource`'s interface or behaviour.

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
| Create | `Sources/Storage/UploadSource.swift` |
| Modify | `Sources/Storage/TUSUploadEngine.swift` — remove `UploadSource`, import from new file |
| Modify | `Sources/Storage/StorageFileAPI.swift` — add 8 new methods (`uploadMultipart`, `uploadResumable`, `updateMultipart`, `updateResumable` × 2 variants each), keep existing `upload`/`update` as smart defaults |

---

## Testing

### Unit tests (`Tests/StorageTests/`)

- `MultipartUploadEngineTests.swift` — mock HTTP session; assert multipart body structure, progress events fire, completion delivers `FileUploadResponse`, cancel stops the task
- `StorageFileAPITests.swift` — add tests for each of the 12 new methods; assert correct engine is chosen in smart default (mock responses for both paths), `uploadMultipart` / `uploadResumable` call the right engine regardless of size

### Integration tests (`Tests/IntegrationTests/`)

- Add `multipartUploadCompletesAndFileExists` — upload ≤ 6 MB via `uploadMultipart`, download and verify bytes match
- Add `smartDefaultUsesMultipartForSmallFile` — upload 1 KB via `upload()`, verify it completes (can't observe engine selection directly, but success confirms the path)
- Add `smartDefaultUsesTUSForLargeFile` — upload 13 MB via `upload()`, verify it completes in chunks
