# Storage

An app manages buckets and files through `client.storage`: it creates a bucket, uploads and
lists files, downloads bytes, shares a signed URL, and removes files and buckets.

## Sub-features

- `storage-bucket-create` creates a private bucket and returns its name.
- `storage-upload` uploads bytes with a content type.
- `storage-list` lists the objects in a folder.
- `storage-download` downloads the object and gets the same bytes.
- `storage-signed-url` signs a URL that a plain HTTP client can fetch without credentials.
- `storage-remove` removes the object and returns it.
- `storage-bucket-delete` deletes the empty bucket; `listBuckets()` no longer shows it.

## How to get to it (user POV)

- `client.storage.createBucket(_:options:)`, `.listBuckets()`, `.deleteBucket(_:)`
- `client.storage.from(bucket).upload(path:data:options:)`
- `client.storage.from(bucket).list(path:)`
- `client.storage.from(bucket).download(path:)` then `.data()`
- `client.storage.from(bucket).createSignedURL(path:expiresIn:)`
- `client.storage.from(bucket).remove(paths:)`

## Driving it with verify.sh

Preconditions:

- A run from `$V up` is live and `$V doctor` is all `ok`.
- The journey uses the service role key, as a server would. Bucket admin needs it.

- **Create bucket.** Run `$V drive storage`. Step `storage-bucket-create` passes. The
  transcript prints `BUCKET bucket-<run-id>-<hex>`.
- **Upload.** Step `storage-upload` uploads `docs/hello.txt` as `text/plain`.
- **List.** Step `storage-list` saves `storage-list.json` with `["hello.txt"]`.
- **Download.** Step `storage-download` shows the text `hello from <run-id>`.
- **Signed URL.** Step `storage-signed-url` fetches the URL with `URLSession` and no keys,
  gets HTTP 200 and the same bytes, and saves the URL and status to `storage-signed-url.json`.
- **Remove.** Step `storage-remove` returns `["docs/hello.txt"]`. Step
  `storage-bucket-delete` shows the bucket gone.
- **Outside view.** Run `$V http GET /storage/v1/bucket`. The journey's bucket is absent after
  the run. To see a file while it exists, drive a copy of the journey that stops before
  `storage-remove`, then run `$V http GET "/storage/v1/object/info/<bucket>/docs/hello.txt"`.

## Gotchas

- `download(path:)` returns a streaming `DownloadResponse`. Call `.data()` to read the body.
- `createSignedURL` takes a `Duration` (`.seconds(60)`), not an `Int`.
- The native stack has no object versioning, lifecycle rules, analytics buckets, or CDN purge.
  Calls to those fail on this stack. They need the Docker stack and
  `./scripts/enable-storage-test-features.sh`, which this skill does not set up.
- Storage uploads live outside the database. `supabase stack destroy` keeps them, so they stay
  under the CLI's data folder after `$V down`.
