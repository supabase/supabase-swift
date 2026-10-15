# Uploading Files

Send bytes, a file, a stream or a `Transferable` item to a bucket, and set how Storage serves it.

## Overview

Each upload is one request. Pick the overload that matches where the bytes live. All of them
return an ``UploadedObject`` and throw ``StorageError``. The bucket must exist.

| Source | Method |
| --- | --- |
| `Data` in memory | ``StorageBucket/upload(path:data:options:progress:)`` |
| A file on disk | ``StorageBucket/upload(path:fileURL:options:progress:)`` |
| A stream of chunks | ``StorageBucket/upload(path:body:options:progress:)`` |
| A `Transferable` value | ``StorageBucket/upload(path:item:contentType:options:progress:)`` |

For a large file on a flaky network, use a resumable upload instead. See <doc:ResumableUploads>.

### Data and files

```swift
let avatars = supabase.storage.from("avatars")

let object = try await avatars.upload(path: "user123.png", data: imageData)
print(object.fullPath)  // "avatars/user123.png"

try await avatars.upload(path: "videos/intro.mov", fileURL: movieURL)
```

The file overload streams the file from disk, so it never sits in memory at once. Prefer it for
anything large.

### Streams

``StorageBucket/upload(path:body:options:progress:)`` takes an `HTTPBody`, an `AsyncSequence` of
byte chunks. Give it a known length when you have one: Storage then refuses an object over the
bucket's size limit before any byte is sent. With an unknown length the body goes out chunked,
and the upload fails only once it passes the limit.

```swift
let body = HTTPBody(chunks, length: .known(size), iterationBehavior: .single)
try await supabase.storage.from("videos").upload(path: "clip.mov", body: body)
```

A body with `.single` iteration cannot be sent twice, so the SDK never retries it.

### Transferable items

``StorageBucket/upload(path:item:contentType:options:progress:)`` exports the item as
`contentType` to a temporary file, uploads that file, then deletes it. The type's preferred MIME
type becomes the object's `Content-Type`, unless ``UploadOptions/contentType`` sets one.

```swift
struct Report: Transferable {
  var pdf: Data

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .pdf) { $0.pdf }
  }
}

try await supabase.storage.from("reports").upload(path: "q3.pdf", item: report, contentType: .pdf)
```

An item that cannot export `contentType` throws ``StorageError`` with kind `invalidRequest`.

A `PhotosPickerItem` is not `Transferable` itself. Load it as a type that imports a file, then
upload the file:

```swift
struct Movie: Transferable {
  let url: URL

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
      let copy = URL.temporaryDirectory.appending(path: received.file.lastPathComponent)
      try FileManager.default.copyItem(at: received.file, to: copy)
      return Movie(url: copy)
    }
  }
}

if let movie = try await pickerItem.loadTransferable(type: Movie.self) {
  try await supabase.storage.from("videos").upload(path: "clip.mov", fileURL: movie.url)
}
```

### Upload options

``UploadOptions`` sets how Storage stores and serves the object.

```swift
let options = UploadOptions(
  contentType: "image/png",
  cacheControl: .maxAge(.seconds(86400)),
  upsert: true,
  metadata: ["owner": "user123"],
  headers: [HTTPField.Name("x-trace")!: traceID]
)
try await avatars.upload(path: "user123.png", data: imageData, options: options)
```

- ``UploadOptions/cacheControl`` is stored with the object and sent back on every download. It
  defaults to one hour. Use ``CacheControl/maxAge(_:)``, ``CacheControl/noCache``,
  ``CacheControl/noStore``, or a string literal for any other directive.
- ``UploadOptions/contentType`` is the object's `Content-Type`. When it is `nil`, the SDK infers
  it: from the file's extension for a file URL, otherwise from the extension of `path`, and
  `application/octet-stream` when neither is known. Linux has no `UTType`, so there the SDK
  uses a table of common types.
- ``UploadOptions/metadata`` is your own JSON, stored with the object. It comes back as
  ``StorageObject/userMetadata`` and ``ObjectInfo/userMetadata``.
- ``UploadOptions/headers`` go out with the upload request. A header set there wins over the one
  the SDK would send, including `Content-Type` and `Cache-Control`.

### Replacing an object

An upload to a path that holds an object fails with ``StorageError/Code/keyAlreadyExists``. To
replace it, set ``UploadOptions/upsert`` to `true`, or call ``StorageBucket/update(path:data:options:progress:)``.

```swift
try await avatars.upload(path: "user123.png", data: newData, options: UploadOptions(upsert: true))
try await avatars.update(path: "user123.png", data: newData)
```

`update` always replaces and ignores `upsert`. It has the same file and stream overloads as
`upload`.

### Progress

Every upload takes a `progress` closure. It receives a ``TransferProgress`` once per chunk sent,
with no throttling, on no particular actor. Hop to the main actor before you touch UI state.

```swift
try await avatars.upload(path: "video.mp4", fileURL: url) { progress in
  Task { @MainActor in model.fraction = progress.fractionCompleted ?? 0 }
}
```

``TransferProgress/fractionCompleted`` is `nil` when the total size is unknown.

### Signed upload URLs

A signed upload URL lets someone without your credentials upload one object. Create it with
``StorageBucket/createSignedUploadURL(path:upsert:)``; it is valid for two hours. Pass its
``SignedUploadURL/token`` to ``StorageBucket/uploadToSignedURL(path:token:data:options:progress:)``.

```swift
let signed = try await avatars.createSignedUploadURL(path: "user123.png", upsert: true)

// Later, perhaps on another device:
try await avatars.uploadToSignedURL(path: "user123.png", token: signed.token, data: imageData)
```

The token decides whether the upload may replace an object, so ``UploadOptions/upsert`` has no
effect here. Storage returns no object id for a signed-URL upload, so ``UploadedObject/id`` is
`nil`.
