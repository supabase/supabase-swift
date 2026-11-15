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
- **Token errors are wrapped.** A token provider that throws (an `AccessTokenMiddleware`, or the
  session through `SupabaseClient`) gives `StorageError` with kind `.accessToken`; the original is
  in `underlyingError`.
- **Cancellation.** A cancelled Storage call throws `CancellationError`, not
  `URLError(.cancelled)`.
- **Reads retry.** Transient failures of `GET` and `HEAD` requests now retry with backoff. Pass
  `retryEnabled: false` to `StorageClient.Configuration` to turn this off.
- **Headers are case-insensitive.** A `content-type` header now replaces `Content-Type` instead of
  sending both. A `Content-Type` in `UploadOptions.headers` wins over the inferred type.
- **`update(path:)` ignores `upsert`.** `update` sends `PUT`, which always replaces. A signed-URL
  upload takes upsert from its token.
- **A discarded download reads nothing.** `_ = try await bucket.download(path:)` returns after the
  response headers and does not read the body.
- **`configuration.headers` holds only the headers you passed.** `StorageClient.configuration`
  no longer contains the SDK's default `X-Client-Info`. The client still sends it on every
  request unless you set that header. Search for code that reads
  `configuration.headers[.xClientInfo]`.

## Renames and type changes

| v2 | v3 |
| --- | --- |
| `SupabaseStorageClient` | `StorageClient` |
| `StorageFileApi` | `StorageBucket` |
| `class` `SupabaseStorageClient`, `StorageFileApi` | `struct` (no `weak`, `===`, or `AnyObject`) |
| `StorageBucketApi`, `StorageApi` | removed; use `StorageClient` |
| `StorageClientConfiguration` | `StorageClient.Configuration` |
| `StorageClientConfiguration(..., session:)` | `StorageClient.Configuration(..., http:)` (see the overview) |
| `StorageClientConfiguration(..., encoder:, decoder:)` | removed |
| `StorageClientConfiguration.useNewHostname` | `StorageClient.Configuration.usesNewHostname` |
| `StorageClientConfiguration(url:headers:...)`, `headers` required | `StorageClient.Configuration(url:headers:usesNewHostname:http:logger:retryEnabled:clock:)`, `headers` defaults to `[:]` |
| `StorageHTTPSession` | `any ClientTransport` (see the overview) |
| `JSONEncoder.defaultStorageEncoder`, `JSONDecoder.defaultStorageDecoder` | removed |
| `getBucket(_:)` | `bucket(_:)` |
| `createBucket(_:options:)` returns `Void` | returns the stored bucket name (`@discardableResult`) |
| `getPublicURL(path:...) throws` | `publicURL(path:...)`, does not throw |
| `upload(_:data:)`, `update(_:data:)`, `uploadToSignedURL(_:token:data:)` | `upload(path:data:)`, `update(path:data:)`, `uploadToSignedURL(path:token:data:)` (same for `fileURL:`) |
| `download: Bool`, `download: String?` | `download: DownloadBehavior?` (`.withOriginalName`, `.named("a.pdf")`), in the options type (see below) |
| `expiresIn: Int` | `expiresIn: Duration`, e.g. `.seconds(60)` |
| `TransformOptions` | `ImageTransform` |
| `FileOptions` | `UploadOptions` (see below) |
| `CreateSignedUploadURLOptions(upsert:)` | `createSignedUploadURL(path:upsert:)` |
| `SignedURL` | removed |
| `FileObject` | `StorageObject` |
| `FileObjectV2` | `ObjectInfo` |
| `FileUploadResponse`, `SignedURLUploadResponse` | `UploadedObject` (`id` is `nil` after a signed-URL upload) |
| `copy(...) -> String` | `copy(...) -> UploadedObject`; the old string is `.fullPath` |
| `BucketOptions` | `CreateBucketOptions` or `UpdateBucketOptions` (see below) |
| `StorageByteCount`, `.intValue`, `.stringValue` | `ByteCount`, `.bytes`, `.rawValue` |
| `Bucket.owner: String` | `Bucket.ownerID: String?` |
| `Bucket(id:name:owner:...)` | `Bucket(id:name:type:ownerID:...)` |
| `Codable` `Bucket` | `Decodable` |
| `Codable` `ResizeMode`, `ImageFormat` | not `Codable`; use `rawValue` |
| `Codable` `SortOrder` | `Encodable` |
| `Storage.File`, `Storage.FormData` | removed |
| any other API marked deprecated in v2 | removed; apply the v2 fix-it first |

## `setHeader` is `settingHeader` and returns a new value

`StorageClient.Configuration.headers` is `HTTPFields`. `setHeader(_:forKey:)` is
`settingHeader(name:value:)`. It no longer changes the receiver: it returns a copy with the header.
Use the returned value.

```swift
// v2
StorageClientConfiguration(url: url, headers: ["apikey": key])
storage.setHeader("v", forKey: "X-Custom")
try await storage.from("avatars").list()
// v3
StorageClient.Configuration(url: url, headers: [.apikey: key])
let custom = storage.settingHeader(name: HTTPField.Name("X-Custom")!, value: "v")
try await custom.from("avatars").list()
```

## `StorageError` is a struct

`StorageError` has `kind`, `message`, `code`, `isNotFound`, `serverError`, `response` and
`underlyingError`. The body's `code` is `StorageError.code`, a `StorageError.Code?` that is `nil`
when Storage sent no code. The body fields `statusCode` and `error` moved to `serverError`, and
`statusCode` is an `Int?`. Every failed request throws `StorageError`, never `HTTPError`.
`StorageError` and `StorageError.ServerError` are not `Decodable`.

```swift
// v2
} catch let error as StorageError where error.statusCode == "404" {
  print(error.error ?? "", error.message)
}
// v3
} catch let error as StorageError where error.isNotFound {
  print(error.serverError?.error ?? "", error.message)
} catch StorageError.Code.keyAlreadyExists {
  // ...
}
```

Branch on `isNotFound`, `code` or `serverError?.statusCode`. A `catch` clause can name a code or a
kind directly, as in `catch StorageError.Code.noSuchKey` or `catch StorageError.Kind.transport`.
Storage sends HTTP 400 for most failures and puts the real status in the body, so
`response?.status` is usually `400 Bad Request`.

A resumable upload error has no `code`. The tus routes answer with a plain-text body and no code,
and the SDK no longer guesses one from the status. Branch on `serverError?.statusCode` instead:
`404` for an upload that is gone, `409` for a path that already holds an object, and `413` for a
file that is too large.

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

`download(path:options:progress:)` returns a `DownloadResponse` as soon as the headers
arrive. Read the body with `data()`, or write it to disk with `write(to:)`. The image transform
(v2 `options:`), `query:`, and `cacheNonce:` move into `DownloadOptions`, which also has `range`,
`versionID` and `headers`.

```swift
// v2
let data = try await bucket.download(path: "a.png", cacheNonce: "v2")
let thumb = try await bucket.download(path: "a.png", options: TransformOptions(width: 64))
let old = try await bucket.download(
  path: "a.png", query: [URLQueryItem(name: "versionId", value: id)])
// v3
let data = try await bucket.download(
  path: "a.png", options: DownloadOptions(cacheNonce: "v2")).data()
let thumb = try await bucket.download(
  path: "a.png", options: DownloadOptions(transform: ImageTransform(width: 64))).data()
let old = try await bucket.download(path: "a.png", options: DownloadOptions(versionID: id)).data()
try await bucket.download(path: "a.mov").write(to: fileURL)
```

The body can be read once.

## `createSignedURL`, `createSignedURLs`, and `publicURL` take options

`download:`, the image transform, and `cacheNonce:` move into `SignedURLOptions`,
`SignedURLsOptions`, and `PublicURLOptions`. `SignedURLOptions` and `PublicURLOptions` also have
`versionID`. The transform is `transform:`, not `options:`.

```swift
// v2
let url = try await bucket.createSignedURL(
  path: "a.pdf", expiresIn: 60, download: .withOriginalName)
let urls = try await bucket.createSignedURLs(paths: ["a.pdf"], expiresIn: 60, cacheNonce: "v2")
let thumb = try bucket.getPublicURL(path: "a.png", options: TransformOptions(width: 64))
// v3
let url = try await bucket.createSignedURL(
  path: "a.pdf", expiresIn: .seconds(60),
  options: SignedURLOptions(download: .withOriginalName))
let urls = try await bucket.createSignedURLs(
  paths: ["a.pdf"], expiresIn: .seconds(60), options: SignedURLsOptions(cacheNonce: "v2"))
let thumb = bucket.publicURL(
  path: "a.png", options: PublicURLOptions(transform: ImageTransform(width: 64)))
```

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

## Acronyms use uniform case

Storage names spell `ID` in capitals, like the rest of the SDK. The wire format does not change.

| v3 pre-release | v3 |
| --- | --- |
| `versionId`, `sourceVersionId` (options and parameters) | `versionID`, `sourceVersionID` |
| `ObjectVersion.versionId` | `ObjectVersion.versionID` |
| `ObjectInfo.bucketId`, `ResumableUpload.bucketId` | `ObjectInfo.bucketID`, `ResumableUpload.bucketID` |
| `Bucket.ownerId` | `Bucket.ownerID` |
| `StorageError.Code.invalidUploadId`, `.invalidAccessKeyId` | `.invalidUploadID`, `.invalidAccessKeyID` |

## One type and one name per field

A field has the same name and type when you send it and when you read it back. The wire format
does not change. From v2, apply the renames above first.

| v3 pre-release | v3 |
| --- | --- |
| `StorageObject.version`, `ObjectInfo.version` | `versionID`, the name the options and `ObjectVersion` use |
| `ObjectInfo.cacheControl`, `ObjectMetadata.cacheControl`, `DownloadResponse.cacheControl: String?` | `CacheControl?`, the type `UploadOptions` and `CopyOptions` take; read the header string with `.rawValue` |
| `[String: JSONValue]` metadata fields | `JSONObject`, the same type; no code change |

`CacheControl` is `ExpressibleByStringLiteral`, so a comparison such as
`info.cacheControl == "no-cache"` still compiles. Code that passes the value on as a `String`
needs `.rawValue`:

```swift
// v3 pre-release
let header: String? = try await bucket.info(path: "a.png").cacheControl

// v3
let header: String? = try await bucket.info(path: "a.png").cacheControl?.rawValue
```

`Bucket.ownerID` stays a `String`: Storage stores the JWT `sub`, which is not a UUID under
third-party auth.

## Experimental APIs

Resumable uploads (`StorageBucket.resumableUpload(path:fileURL:options:)`, `ResumableUpload`,
`StorageClient.Configuration.resumable`), `storage.vectors` and `storage.analytics` are
`@_spi(Experimental)`. Import them with `@_spi(Experimental) import Supabase` (or
`@_spi(Experimental) import Storage`). They may change in any release. The Vectors list methods now
return a `PageSequence` and take `pageSize` instead of `maxResults`. Their pages are
`VectorBucketPage`, `VectorIndexPage`, and `VectorPage`; call `.page()` for the first page.
`listBuckets`, `listIndexes`, `vectors(keys:)`, `listVectors`, and `queryVectors` take their
optional settings in `ListVectorBucketsOptions`, `ListIndexesOptions`, `GetVectorsOptions`,
`ListVectorsOptions`, and `QueryVectorsOptions`. The vector models have public memberwise inits
for fixtures.

`VectorBucketClient` follows the same getter pattern as `StorageClient`: `from(_:)` returns a
client and the noun returns details.

| v2 | v3 |
|----|----|
| `vectors.listBuckets(prefix: "docs", maxResults: 100)` | `vectors.listBuckets(options: .init(prefix: "docs", pageSize: 100))` |
| `try await vectors.getBucket("docs")` | `try await vectors.bucket("docs")` |
| `bucket.listIndexes(prefix: "emb", maxResults: 100)` | `bucket.listIndexes(options: .init(prefix: "emb", pageSize: 100))` |
| `bucket.index("embeddings")` (a `VectorIndexClient`) | `bucket.from("embeddings")` |
| `try await bucket.getIndex("embeddings")` (a `VectorIndex`) | `try await bucket.index("embeddings")` |
