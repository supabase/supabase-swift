# Storage v3 migration

This file covers the changes to `StorageClient`, `StorageBucket` and the Storage types from v2 to
v3. See [the v3 migration overview](../../../V3_MIGRATION.md) for steps that apply to every module,
including `supabase.storage` and the `http:` transport.

## Silent changes

Changes that still compile but behave differently. Check each one by hand.

- **Uploads send the raw file body.** `upload`, `update` and `uploadToSignedURL` no longer send
  `multipart/form-data`. The file is the body, `Content-Type` is the file type, and `metadata`
  travels as base64 JSON in the `x-metadata` header. Update any middleware, proxy rule or test
  fixture that matches on `multipart/form-data` or `boundary=`.
- **Object paths are normalized.** Every method drops leading and trailing `/`, collapses `//`
  and percent-encodes each segment (`+` becomes `%2B`). An empty path, or a path with a `.` or
  `..` segment, throws `StorageError` with kind `.invalidRequest` before the request goes out.
  Search for paths that you build from user input.
- **`exists(path:)` throws.** It returns `false` only for a missing key. A missing bucket, an
  expired token or any other failure now throws. In v2 any 400 or 404 returned `false`.
- **Network and decoding errors are wrapped.** `URLError` and `DecodingError` arrive as
  `StorageError` with kind `.transport` or `.decoding`; the original is in `underlyingError`.
  Search for `as URLError` and `as DecodingError` near Storage calls.
- **Cancellation.** A cancelled Storage call throws `CancellationError`, not
  `URLError(.cancelled)`.
- **Reads retry.** Transient failures of `GET` and `HEAD` requests now retry with backoff. Pass
  `retryEnabled: false` to `StorageClientConfiguration` to turn this off.
- **Headers are case-insensitive.** A `content-type` header now replaces `Content-Type` instead of
  sending both. A `Content-Type` in `UploadOptions.headers` wins over the inferred type.
- **`update(path:)` ignores `upsert`.** `update` sends `PUT`, which always replaces. A signed-URL
  upload takes upsert from its token.
- **A discarded download reads nothing.** `_ = try await bucket.download(path:)` returns after the
  response headers and does not read the body.

## Renames and type changes

| v2 | v3 |
| --- | --- |
| `SupabaseStorageClient` | `StorageClient` |
| `StorageFileApi` | `StorageBucket` |
| `class` `SupabaseStorageClient`, `StorageFileApi` | `struct` (no `weak`, `===`, or `AnyObject`) |
| `StorageBucketApi`, `StorageApi` | removed; use `StorageClient` |
| `StorageClientConfiguration(..., session:)` | `StorageClientConfiguration(..., http:)` (see the overview) |
| `StorageClientConfiguration(..., encoder:, decoder:)` | removed |
| `StorageClientConfiguration.useNewHostname` | `usesNewHostname` |
| `StorageHTTPSession` | `any ClientTransport` (see the overview) |
| `JSONEncoder.defaultStorageEncoder`, `JSONDecoder.defaultStorageDecoder` | removed |
| `getBucket(_:)` | `bucket(_:)` |
| `createBucket(_:options:)` returns `Void` | returns the stored bucket name (`@discardableResult`) |
| `getPublicURL(path:...) throws` | `publicURL(path:...)`, does not throw |
| `upload(_:data:)`, `update(_:data:)`, `uploadToSignedURL(_:token:data:)` | `upload(path:data:)`, `update(path:data:)`, `uploadToSignedURL(path:token:data:)` (same for `fileURL:`) |
| `download: Bool`, `download: String?` | `download: DownloadBehavior?` (`.withOriginalName`, `.named("a.pdf")`) |
| `expiresIn: Int` | `expiresIn: Duration`, e.g. `.seconds(60)` |
| `TransformOptions` | `ImageTransform` |
| `download(path:options:)`, `getPublicURL(path:options:)` | `download(path:transform:)`, `publicURL(path:transform:)` |
| `FileOptions` | `UploadOptions` (see below) |
| `CreateSignedUploadURLOptions(upsert:)` | `createSignedUploadURL(path:upsert:)` |
| `SignedURL` | removed |
| `FileObject` | `StorageObject` |
| `FileObjectV2` | `ObjectInfo` |
| `FileUploadResponse`, `SignedURLUploadResponse` | `UploadedObject` (`id` is `nil` after a signed-URL upload) |
| `copy(...) -> String` | `copy(...) -> UploadedObject`; the old string is `.fullPath` |
| `BucketOptions` | `CreateBucketOptions` or `UpdateBucketOptions` (see below) |
| `StorageByteCount`, `.intValue`, `.stringValue` | `ByteCount`, `.bytes`, `.rawValue` |
| `Bucket.owner: String` | `Bucket.ownerId: String?` |
| `Bucket(id:name:owner:...)` | `Bucket(id:name:type:ownerId:...)` |
| `Codable` `Bucket` | `Decodable` |
| `Codable` `ResizeMode`, `ImageFormat` | not `Codable`; use `rawValue` |
| `Codable` `SortOrder` | `Encodable` |
| `Storage.File`, `Storage.FormData` | removed |
| any other API marked deprecated in v2 | removed; apply the v2 fix-it first |

## `setHeader` takes an `HTTPField.Name` and returns a new value

`StorageClientConfiguration.headers` is `HTTPFields`. `setHeader(_:forKey:)` is
`setHeader(name:value:)`. It no longer changes the receiver: it returns a copy with the header.
Use the returned value.

```swift
// v2
StorageClientConfiguration(url: url, headers: ["apikey": key])
storage.setHeader("v", forKey: "X-Custom")
try await storage.from("avatars").list()
// v3
StorageClientConfiguration(url: url, headers: [HTTPField.Name("apikey")!: key])
let custom = storage.setHeader(name: HTTPField.Name("X-Custom")!, value: "v")
try await custom.from("avatars").list()
```

## `StorageError` is a struct with `kind`

`StorageError` has `kind`, `message`, `code`, `serverStatusCode`, `isNotFound`, `serverError`,
`response` and `underlyingError`. The body fields `statusCode` and `error` moved to
`serverError`, and `statusCode` is an `Int?`. Every failed request throws `StorageError`, never
`HTTPError`. `StorageError` is not `Decodable`.

```swift
// v2
} catch let error as StorageError where error.statusCode == "404" {
  print(error.error ?? "", error.message)
}
// v3
} catch let error as StorageError where error.isNotFound {
  print(error.serverError?.error ?? "", error.message)
} catch let error as StorageError where error.code == .keyAlreadyExists {
  // ...
}
```

Branch on `isNotFound`, `code` or `serverStatusCode`. Storage sends HTTP 400 for most failures and
puts the real status in the body, so `response?.statusCode` is usually 400.

## `UploadOptions` replaces `FileOptions`

`cacheControl` is a `CacheControl`, not a string of seconds. `headers` is `HTTPFields`. `duplex`
is removed. `uploadToSignedURL` takes `UploadOptions`, not `UploadOptions?`.

```swift
// v2
try await bucket.upload(
  "a.png", data: data,
  options: FileOptions(cacheControl: "86400", contentType: "image/png", upsert: true))
// v3
try await bucket.upload(
  path: "a.png", data: data,
  options: UploadOptions(
    contentType: "image/png", cacheControl: .maxAge(.seconds(86400)), upsert: true))
```

`CacheControl` also has `.noCache`, `.noStore`, and accepts any string literal as the full
header value.

## `download` returns a streaming `DownloadResponse`

`download(path:transform:options:progress:)` returns a `DownloadResponse` as soon as the headers
arrive. Read the body with `data()`, or write it to disk with `write(to:)`. `query:` and
`cacheNonce:` move into `DownloadOptions`, which also has `range`, `versionId` and `headers`.

```swift
// v2
let data = try await bucket.download(path: "a.png", cacheNonce: "v2")
let old = try await bucket.download(
  path: "a.png", query: [URLQueryItem(name: "versionId", value: id)])
// v3
let data = try await bucket.download(
  path: "a.png", options: DownloadOptions(cacheNonce: "v2")).data()
let old = try await bucket.download(path: "a.png", options: DownloadOptions(versionId: id)).data()
try await bucket.download(path: "a.mov").write(to: fileURL)
```

The body can be read once.

## Object types: `StorageObject` and `ObjectInfo`

`list` and `remove` return `[StorageObject]`. `info` returns `ObjectInfo`. Ids are `UUID`, sizes
are `Int64`. The server's file metadata is a typed `ObjectMetadata`. The uploader's metadata is
`userMetadata`. `FileObject.bucketId`, `.owner` and `.buckets` are removed.

```swift
// v2
let files: [FileObject] = try await bucket.list()
let size = files[0].metadata?["size"]?.intValue
let info: FileObjectV2 = try await bucket.info(path: "a.png")
print(info.etag ?? "", info.metadata ?? [:])
// v3
let files: [StorageObject] = try await bucket.list()
let size = files[0].metadata?.size
let info: ObjectInfo = try await bucket.info(path: "a.png")
print(info.eTag ?? "", info.userMetadata ?? [:])
```

## `ListOptions` replaces `SearchOptions` and `SortBy`

`list(path:options:)` takes a non-optional `ListOptions`. The sort is two fields: `sortBy` is an
`ObjectSortColumn` and `order` is a `SortOrder`.

```swift
// v2
let files = try await bucket.list(
  path: "photos",
  options: SearchOptions(limit: 50, sortBy: SortBy(column: "created_at", order: .descending)))
// v3
let files = try await bucket.list(
  path: "photos", options: ListOptions(limit: 50, sortBy: .createdAt, order: .descending))
```

## `BucketOptions` is split into `CreateBucketOptions` and `UpdateBucketOptions`

`createBucket` takes `CreateBucketOptions`. `updateBucket` takes `UpdateBucketOptions`. Every field
is optional and `nil` by default. `updateBucket` sends only the fields you set, so it no longer
resets `isPublic` to `false`. It throws `.invalidRequest` when no field is set.

```swift
// v2
try await storage.createBucket(
  "logs", options: BucketOptions(isPublic: true, fileSizeLimit: "5mb"))
try await storage.updateBucket(
  "avatars", options: BucketOptions(isPublic: true, allowedMimeTypes: ["image/png"]))
// v3
try await storage.createBucket(
  "logs", options: CreateBucketOptions(isPublic: true, fileSizeLimit: .megabytes(5)))
try await storage.updateBucket(
  "avatars", options: UpdateBucketOptions(allowedMimeTypes: ["image/png"]))
```

An inline `options: .init(isPublic: true)` compiles unchanged.

## `move` and `copy` take `toBucket:`

`DestinationOptions` is removed. Pass the destination bucket as `toBucket:`.

```swift
// v2
try await bucket.move(
  from: "a.png", to: "a.png", options: DestinationOptions(destinationBucket: "archive"))
let key: String = try await bucket.copy(from: "a.png", to: "b.png")
// v3
try await bucket.move(from: "a.png", to: "a.png", toBucket: "archive")
let key: String = try await bucket.copy(from: "a.png", to: "b.png").fullPath
```

## Experimental APIs

Resumable uploads (`StorageBucket.resumableUpload(path:fileURL:options:)`, `ResumableUpload`,
`StorageClientConfiguration.resumable`), `storage.vectors` and `storage.analytics` are
`@_spi(Experimental)`. Import them with `@_spi(Experimental) import Supabase` (or
`@_spi(Experimental) import Storage`). They may change in any release. The Vectors list methods now
return a `PagedListing`; call `.page()` for the first page.
