# Image Transformations

Resize, crop and reformat an image on the server before it is sent.

## Overview

An ``ImageTransform`` describes the image you want. Storage renders it from the stored object,
so you upload one original and serve every size from it. Pass the same value to any of three
methods:

- ``StorageBucket/publicURL(path:download:transform:versionId:cacheNonce:)`` for a public bucket.
- ``StorageBucket/createSignedURL(path:expiresIn:download:transform:versionId:cacheNonce:)`` for
  a private bucket.
- ``StorageBucket/download(path:transform:options:progress:)`` to fetch the bytes.

```swift
let avatars = supabase.storage.from("avatars")
let transform = ImageTransform(width: 200, height: 200, resize: .cover, quality: 80)

let publicURL = avatars.publicURL(path: "user123.png", transform: transform)
let signedURL = try await avatars.createSignedURL(
  path: "user123.png", expiresIn: .seconds(3600), transform: transform)
let data = try await avatars.download(path: "user123.png", transform: transform).data()
```

### Size and fit

``ImageTransform/width`` and ``ImageTransform/height`` are in pixels. ``ImageTransform/resize``
says how the image fits them:

- ``ResizeMode/cover``, the default, fills the box and crops the overflow.
- ``ResizeMode/contain`` fits the whole image inside the box.
- ``ResizeMode/fill`` stretches the image to the box, ignoring its aspect ratio.

### Format and quality

``ImageTransform/format`` picks the output format: ``ImageFormat/webp``, ``ImageFormat/avif``, or
``ImageFormat/origin`` to keep the source format. When it is `nil`, the source format is kept.
``ImageTransform/quality`` runs from 20 to 100 and defaults to 80.

### Cropping

A ``ResizeMode/cover`` crop keeps the center by default. ``ImageTransform/gravity`` picks another
part: an edge such as ``Gravity/north``, a corner, ``Gravity/smart`` to let the server choose, or
``Gravity/focalPoint`` with a ``FocalPoint``.

```swift
let face = ImageTransform(
  width: 200, height: 200, gravity: .focalPoint, focalPoint: FocalPoint(x: 0.3, y: 0.4))
```

A ``FocalPoint`` is a fraction of the width and height, measured from the top-left corner.

### Responses

A transformed download has no `Content-Length`, so ``DownloadResponse/contentLength`` and
``TransferProgress/totalBytes`` are `nil`. For a public URL or a download, a transform with no fields set
is not sent, and the request goes to the plain object route.
