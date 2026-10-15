# Handling Errors

Tell a missing file from a network failure, and read what Storage reported.

## Overview

Every failure from ``StorageClient`` and ``StorageBucket`` is a ``StorageError`` or a
`CancellationError`. Check ``StorageError/kind`` first.

A few errors are not Storage's and reach you as themselves: the file system's error when a file
cannot be read or written, and `HTTPBodyTooLargeError` when ``DownloadResponse/data(upTo:)``
passes its cap.

| Kind | When | Set |
| --- | --- | --- |
| ``StorageError/Kind-swift.struct/server`` | Storage answered with a non-2xx status. | ``StorageError/response``, and usually ``StorageError/code`` |
| ``StorageError/Kind-swift.struct/transport`` | No response arrived, or the connection dropped while a body streamed. | ``StorageError/underlyingError``, usually a `URLError` |
| ``StorageError/Kind-swift.struct/decoding`` | A 2xx body could not be used. | ``StorageError/underlyingError``, the `DecodingError` |
| ``StorageError/Kind-swift.struct/invalidRequest`` | The SDK refused to send, for example an empty path or a `..` segment. | ``StorageError/message`` |

``StorageError/Kind-swift.struct`` is an open set. Keep a fallback branch.

### Body status and HTTP status

On the object, bucket and render routes, Storage answers nearly every failure with HTTP 400. The
real outcome is in the body. So branch on ``StorageError/code`` or
``StorageError/serverStatusCode``, not on `response?.statusCode`.

```swift
do {
  try await supabase.storage.from("avatars").upload(path: "user123.png", data: imageData)
} catch let error as StorageError where error.code == .keyAlreadyExists {
  askToReplace()
} catch let error as StorageError where error.serverStatusCode == 413 {
  showTooLarge()
}
```

- ``StorageError/code`` is the machine-readable code, such as ``StorageError/Code/noSuchKey``.
- ``StorageError/serverStatusCode`` is the status Storage put in the body, such as `404`.
- ``StorageError/serverError`` is the whole decoded body. It is `nil` when the body was not a
  Storage error payload, for example a page from a proxy.
- ``StorageError/response`` holds the HTTP status, the headers and the body, capped at 1 MiB. Its
  `requestID` is the value to quote to Supabase support.

``StorageError/Code`` is an open set too. Compare against the static members, and keep a
fallback branch: a server newer than the SDK can send a code this version does not know.

### Not found

``StorageError/isNotFound`` is `true` when Storage reports that the object or the bucket does not
exist, whichever of the code, the body status or the HTTP status says so.

```swift
do {
  let data = try await supabase.storage.from("avatars").download(path: "user123.png").data()
  show(data)
} catch let error as StorageError where error.isNotFound {
  showPlaceholder()
}
```

To check for an object without an error, call ``StorageBucket/exists(path:)``.

### Transport failures and retries

A transport failure means no answer arrived, so whether Storage applied the request is unknown.
Reads are safe to retry. Before you retry an upload, a move or a removal, check that it did not
already happen.

The SDK retries reads for you: `GET` and `HEAD` requests and each page of
``StorageBucket/objects(prefix:options:)``, up to three attempts with jittered backoff. It never
replays an upload, a move, a copy, a removal or a bucket change. Turn retries off with ``StorageClientConfiguration/retryEnabled``.

A transport failure can also arrive after a download returned, while you read
``DownloadResponse/body``. Handle errors around the read, not only around the call.

### Cancellation

A cancelled task throws `CancellationError`, never a wrapped error. That includes a loop over a
download body. A `URLError(.cancelled)` with no task cancellation behind it, such as a
middleware that cancels the request, stays a `transport` error.

```swift
do {
  try await bucket.download(path: "video.mp4").write(to: fileURL)
} catch is CancellationError {
  // the user left the screen
} catch let error as StorageError {
  log(error.message)
}
```

Errors from your own code inside the exchange, such as a custom transport, a middleware or the
access token provider, reach you as themselves.
