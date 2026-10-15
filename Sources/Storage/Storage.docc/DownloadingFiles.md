# Downloading Files

Read an object into memory, write it to disk, or process it as it arrives.

## Overview

``StorageBucket/download(path:transform:options:progress:)`` returns a ``DownloadResponse`` as
soon as Storage sends the response headers. Its ``DownloadResponse/body`` streams the object and
can be read once. Choose how to read it.

### Into memory

``DownloadResponse/data(upTo:)`` collects the whole body. Pass a cap when the object size is not
under your control: the read throws `HTTPBodyTooLargeError` once more bytes arrive.

```swift
let avatars = supabase.storage.from("avatars")

let data = try await avatars.download(path: "user123.png").data()
let capped = try await avatars.download(path: "upload.bin").data(upTo: 10 * 1024 * 1024)
```

### To a file

``DownloadResponse/write(to:)`` streams the body to disk, so the object never has to fit in
memory.

```swift
try await supabase.storage.from("videos").download(path: "intro.mov").write(to: fileURL)
```

### Chunk by chunk

The body is an `AsyncSequence` of byte chunks. Chunk sizes follow the network.

```swift
let response = try await supabase.storage.from("logs").download(path: "today.log")
for try await chunk in response.body {
  parser.feed(chunk)
}
```

### Headers

``DownloadResponse`` has typed properties for the common headers:
``DownloadResponse/contentType``, ``DownloadResponse/contentLength``,
``DownloadResponse/contentRange``, ``DownloadResponse/eTag``, ``DownloadResponse/lastModified``
and ``DownloadResponse/cacheControl``. Read any other from ``DownloadResponse/httpResponse``.

```swift
let response = try await avatars.download(path: "user123.png")
print(response.contentType ?? "?", response.contentLength ?? 0)
```

### Download options

``DownloadOptions`` shapes the request.

- ``DownloadOptions/range`` fetches only some bytes, both ends included. Storage answers
  `206 Partial Content`.
- ``DownloadOptions/versionId`` fetches an older version in a bucket with versioning.
- ``DownloadOptions/cacheNonce`` adds a `cacheNonce` query item, so a CDN serves a fresh copy.
- ``DownloadOptions/headers`` go out with the request and win over the SDK's own.

```swift
let head = try await supabase.storage.from("logs")
  .download(path: "today.log", options: DownloadOptions(range: 0...1023))
print(head.contentRange ?? "")  // "bytes 0-1023/52133"
```

### Progress

Pass a `progress` closure to see bytes arrive. It receives a ``TransferProgress`` for each chunk
you read, on no particular actor. ``TransferProgress/totalBytes`` is `nil` when Storage sends no
`Content-Length`, as for a transformed image.

```swift
let response = try await avatars.download(path: "user123.png") { progress in
  Task { @MainActor in model.fraction = progress.fractionCompleted ?? 0 }
}
try await response.write(to: fileURL)
```

Progress counts the bytes you read, so it moves only while you consume the body.

### Image transformations

Pass an ``ImageTransform`` to resize or reformat an image on the server before it is sent. See
<doc:ImageTransformations>.

```swift
let thumbnail = try await avatars
  .download(path: "user123.png", transform: ImageTransform(width: 128, height: 128))
  .data()
```

### Public buckets

For a public bucket, you do not need to download through the SDK. Load the URL from
``StorageBucket/publicURL(path:download:transform:versionId:cacheNonce:)`` directly, for example
with `AsyncImage`. It needs no network call to build.

### Metadata only

``StorageBucket/info(path:versionId:)`` returns an ``ObjectInfo`` without the bytes.
``StorageBucket/exists(path:)`` returns `false` only when Storage reports the key does not exist;
every other failure throws.
