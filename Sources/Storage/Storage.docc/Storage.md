# ``Storage``

Store and serve files in Supabase Storage: uploads, downloads, listings, signed URLs and image
transformations.

## Overview

``StorageClient`` is the client for the `/storage/v1` API. Get one from `supabase.storage`, or
build one on its own with ``StorageClient/init(configuration:)`` (see <doc:Standalone>). It
manages buckets. ``StorageClient/from(_:)`` returns a ``StorageBucket``, the handle for the
files in one bucket.

```swift
let avatars = supabase.storage.from("avatars")
```

Both types are immutable values. Make them as often as you like; they hold no connection.

### Upload

```swift
let object = try await avatars.upload(path: "user123.png", data: imageData)
print(object.fullPath)  // "avatars/user123.png"
```

See <doc:UploadingFiles>.

### Download

```swift
let data = try await avatars.download(path: "user123.png").data()
```

See <doc:DownloadingFiles>.

### List

```swift
for try await object in avatars.objects(prefix: "2026/") {
  print(object.name)
}
```

See <doc:ListingObjects>.

### Share

```swift
let url = try await avatars.createSignedURL(path: "user123.png", expiresIn: .seconds(3600))
let thumbnail = avatars.publicURL(path: "user123.png", transform: ImageTransform(width: 64))
```

See <doc:ImageTransformations>.

Every failure is a ``StorageError`` or a `CancellationError`. See <doc:HandlingErrors>.

## Topics

### Essentials

- <doc:UploadingFiles>
- <doc:DownloadingFiles>
- <doc:ResumableUploads>
- <doc:ListingObjects>
- <doc:ImageTransformations>
- <doc:HandlingErrors>
- <doc:Standalone>

### Clients

- ``StorageClient``
- ``StorageClientConfiguration``
- ``StorageBucket``

### Uploads

- ``UploadOptions``
- ``CacheControl``
- ``UploadedObject``
- ``SignedUploadURL``
- ``TransferProgress``

### Downloads and URLs

- ``DownloadResponse``
- ``DownloadOptions``
- ``DownloadBehavior``
- ``SignedURLResult``

### Image transformations

- ``ImageTransform``
- ``ResizeMode``
- ``ImageFormat``
- ``Gravity``
- ``FocalPoint``

### Listing objects

- ``ObjectListing``
- ``ObjectListingOptions``
- ``PageSequence``
- ``ObjectSortColumn``
- ``SortOrder``
- ``VersionFilter``

### Objects

- ``StorageObject``
- ``ObjectMetadata``
- ``ObjectInfo``
- ``ObjectVersion``
- ``CopyOptions``

### Buckets

- ``Bucket``
- ``BucketType``
- ``BucketVersioningStatus``
- ``BucketVersioningCreateStatus``
- ``BucketVersioningUpdateStatus``
- ``CreateBucketOptions``
- ``UpdateBucketOptions``
- ``BucketListOptions``
- ``BucketSortColumn``
- ``ByteCount``

### Bucket lifecycle

- ``LifecycleConfiguration``
- ``LifecycleRule``
- ``LifecycleRuleStatus``
- ``NoncurrentVersionExpiration``

### Errors

- ``StorageError``
