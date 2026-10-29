// Journey: Storage — create a bucket, upload, list, download, sign a URL, remove, delete the bucket.
// Proof: the SDK's results, the downloaded bytes, and a plain HTTP GET of the signed URL.
import Foundation
import Supabase

// Bucket admin needs the service role, as on a server. Object calls use the same client.
let client = Verify.client(key: Verify.serviceRoleKey)
let bucket = Verify.unique("bucket")
let path = "docs/hello.txt"
let payload = Data("hello from \(Verify.runID)".utf8)

Verify.step("storage-bucket-create", "create private bucket \(bucket)")
let created = await Verify.attempt("storage-bucket-create") {
  try await client.storage.createBucket(bucket, options: .init(isPublic: false))
}
Verify.check("storage-bucket-create", created == bucket, "created \(created ?? "nil")")

Verify.step("storage-upload", "upload \(path) (\(payload.count) bytes, text/plain)")
if let object = await Verify.attempt("storage-upload", {
  try await client.storage.from(bucket).upload(
    path: path, data: payload, options: UploadOptions(contentType: "text/plain"))
}) {
  Verify.check("storage-upload", object.path == path, "uploaded \(object.path)")
}

Verify.step("storage-list", "list folder docs/")
if let items = await Verify.attempt("storage-list", {
  try await client.storage.from(bucket).list(path: "docs")
}) {
  let names = items.map(\.name)
  Verify.save("storage-list.json", names)
  Verify.check("storage-list", names == ["hello.txt"], "names \(names)")
}

Verify.step("storage-download", "download \(path) and compare bytes")
if let bytes = await Verify.attempt("storage-download", {
  try await client.storage.from(bucket).download(path: path).data()
}) {
  Verify.check(
    "storage-download", bytes == payload, "got \(String(decoding: bytes, as: UTF8.self))")
}

Verify.step("storage-signed-url", "sign a 60 s URL and fetch it without credentials")
if let url = await Verify.attempt("storage-signed-url", {
  try await client.storage.from(bucket).createSignedURL(path: path, expiresIn: .seconds(60))
}) {
  let fetched = await Verify.attempt("storage-signed-url-fetch") {
    try await URLSession.shared.data(from: url)
  }
  let status = (fetched?.1 as? HTTPURLResponse)?.statusCode ?? -1
  Verify.save("storage-signed-url.json", ["url": url.absoluteString, "status": "\(status)"])
  Verify.check(
    "storage-signed-url", status == 200 && fetched?.0 == payload, "GET signed URL -> \(status)")
}

Verify.step("storage-remove", "remove the object, then delete the bucket")
if let removed = await Verify.attempt("storage-remove", {
  try await client.storage.from(bucket).remove(paths: [path])
}) {
  Verify.check("storage-remove", removed.map(\.name) == [path], "removed \(removed.map(\.name))")
}
_ = await Verify.attempt("storage-bucket-delete") { try await client.storage.deleteBucket(bucket) }
let buckets = await Verify.attempt("storage-bucket-delete") { try await client.storage.listBuckets() }
Verify.check(
  "storage-bucket-delete", buckets.map { !$0.contains { $0.id == bucket } } ?? false,
  "bucket gone from listBuckets")

print("BUCKET \(bucket)")
Verify.finish()
