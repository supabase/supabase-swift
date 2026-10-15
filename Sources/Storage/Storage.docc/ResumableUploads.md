# Resumable Uploads

Upload a large file in chunks that survive a lost connection, a pause, and an app relaunch.

## Overview

> Warning: Resumable uploads are experimental. The API is behind `@_spi(Experimental)` and may
> change in a future release.

Opt in on the import:

```swift
@_spi(Experimental) import Storage
// or
@_spi(Experimental) import Supabase
```

A resumable upload sends a file over the tus protocol, one chunk per request. The server keeps
every chunk it confirms, so a failed request costs one chunk, not the whole file. Use it for
large files and for uploads that must outlive the app process. For anything small, a plain
upload is simpler. See <doc:UploadingFiles>.

### The upload handle

`StorageBucket.resumableUpload(path:fileURL:options:)` returns a `ResumableUpload` handle. It
sends nothing until you call `start()`. The `data:` overload writes the bytes to disk first, so
that upload can also continue after a relaunch.

```swift
let upload = try supabase.storage.from("videos").resumableUpload(path: "trip.mov", fileURL: url)
try await upload.start()

for await progress in upload.progress {
  print(progress.fractionCompleted ?? 0)
}
let object = try await upload.result
```

- `start()` creates the upload on the server, or finds the one a previous run left. It returns
  once the first request is answered; it does not wait for the whole file.
- `progress` is an `AsyncStream` of ``TransferProgress``, the bytes the server has confirmed. A
  late subscriber gets the latest value first. The stream ends with the upload.
- `states` is an `AsyncStream` of every change of `state`: `pending`, `uploading`, `paused`,
  `completed(_:)`, `failed(_:)` and `cancelled`. It ends after a terminal state.
- `result` waits for the end and returns the ``UploadedObject``, or throws.

A handle outlives the task that made it, like a `Task`. Cancelling a task that awaits `start()`,
`result`, `progress` or `states` ends only that await. The upload keeps going.

The same file to the same path in the same bucket is the same upload. Asking for it again
returns the same handle while one is alive, so two screens never send it twice.

### Pause, resume and cancel

```swift
await upload.pause()
try await upload.resume()
await upload.cancel()
```

| | `pause()` | `cancel()` |
| --- | --- | --- |
| The chunk in flight | lands first | is dropped |
| The server's copy | kept | deleted, best effort |
| The record on disk | kept | deleted, with any copy of the file |
| Afterwards | `resume()` continues from the server's offset | `result` throws `CancellationError` |

`resume()` also continues a failed upload whose record is still on disk.

### Failures and retries

After a network failure the upload asks the server for its offset and retries, with growing
waits. When the waits add up to more than `retryTimeout` (60 seconds by default), the upload
fails with a ``StorageError`` of kind `transport`. Its record stays, so you can call `resume()`
later, in this process or the next.

A server rejection, such as a file over the bucket's size limit, fails the upload and removes
its record. Retrying would fail the same way.

### After a relaunch

Each upload keeps a small record on disk: the server's upload URL, the offset, and where the
bytes are. A file inside the app container is read in place. A file elsewhere, or in the
temporary directory, is copied first, because a picker or `Transferable` URL is gone after the
process ends.

At launch, ask `storage.resumableUploads` for the uploads a previous run left.

```swift
for upload in try await supabase.storage.resumableUploads.resumeAll() {
  Task { _ = try? await upload.result }
}
```

- `pending()` returns a handle for every record, oldest first, without starting them.
- `resumeAll()` returns the same handles, each started or resumed. A server refusal does not
  throw there; it shows in that upload's `state` and `result`.
- `clear()` deletes every record and copy that is not in flight in this process.

A record expires when the server says the upload has, or after 24 hours when the server sends no
expiry. A record whose source file changed size or modification date is stale. A stale record is
removed the next time it is read.

### Configuration

`StorageClientConfiguration.resumable` takes a `ResumableUploadConfiguration`:

- `chunkSize` is the bytes per request. Hosted Supabase accepts exactly 6 MiB, the default, for
  every chunk but the last. Change it only for a self-hosted Storage set up for another size.
- `retryTimeout` is how long the upload retries after a network failure before it fails.
- `directory` is where records and copies live. The default is `Application Support`. Pass an
  app group container to share uploads with an app extension.

```swift
var configuration = StorageClientConfiguration(url: storageURL, headers: headers)
configuration.resumable = ResumableUploadConfiguration(directory: appGroupURL)
let storage = StorageClient(configuration: configuration)
```

A record keeps the chunk size it was created with, so a change applies to new uploads only.

### Storage host

On hosted Supabase, resumable uploads always go to the direct storage host,
`<project-ref>.storage.supabase.co`, as the tus endpoint requires. This happens whatever
``StorageClientConfiguration/usesNewHostname`` says. Other requests are not affected, and a
self-hosted URL is used as it is.
