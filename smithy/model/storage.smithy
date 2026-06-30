$version: "2"

namespace io.supabase.storage

use aws.protocols#restJson1
use io.supabase#StringList

@restJson1
@title("Supabase Storage API")
service StorageService {
  version: "1.0"
  operations: [
    ListBuckets
    GetBucket
    CreateBucket
    UpdateBucket
    EmptyBucket
    DeleteBucket
    MoveObject
    CopyObject
    DeleteObjects
    ListObjects
    GetObjectInfo
    HeadObject
    CreateSignedUrl
    CreateSignedUrls
    CreateSignedUploadUrl
  ]
  errors: [StorageError]
}

// ─── Bucket Operations ─────────────────────────────────────────────────────

@http(method: "GET", uri: "/bucket", code: 200)
@readonly
operation ListBuckets {
  output: ListBucketsOutput
  errors: [StorageError]
}

structure ListBucketsOutput {
  @required
  @httpPayload
  items: BucketList
}

list BucketList {
  member: Bucket
}

@http(method: "GET", uri: "/bucket/{id}", code: 200)
@readonly
operation GetBucket {
  input: GetBucketInput
  output: Bucket
  errors: [StorageError]
}

structure GetBucketInput {
  @required
  @httpLabel
  id: String
}

@http(method: "POST", uri: "/bucket", code: 200)
operation CreateBucket {
  input: CreateBucketInput
  errors: [StorageError]
}

structure CreateBucketInput {
  @required id: String
  @required name: String
  @required @jsonName("public") isPublic: Boolean
  file_size_limit: Long
  allowed_mime_types: StringList
}

@http(method: "PUT", uri: "/bucket/{id}", code: 200)
operation UpdateBucket {
  input: UpdateBucketInput
  errors: [StorageError]
}

structure UpdateBucketInput {
  @required
  @httpLabel
  id: String

  @required @jsonName("public") isPublic: Boolean
  file_size_limit: Long
  allowed_mime_types: StringList
}

@http(method: "POST", uri: "/bucket/{id}/empty", code: 200)
operation EmptyBucket {
  input: EmptyBucketInput
  errors: [StorageError]
}

structure EmptyBucketInput {
  @required
  @httpLabel
  id: String
}

@http(method: "DELETE", uri: "/bucket/{id}", code: 200)
operation DeleteBucket {
  input: DeleteBucketInput
  errors: [StorageError]
}

structure DeleteBucketInput {
  @required
  @httpLabel
  id: String
}

// ─── Object Operations ─────────────────────────────────────────────────────

@http(method: "POST", uri: "/object/move", code: 200)
operation MoveObject {
  input: MoveObjectInput
  errors: [StorageError]
}

structure MoveObjectInput {
  @required bucketId: String
  @required sourceKey: String
  @required destinationKey: String
  destinationBucket: String
}

@http(method: "POST", uri: "/object/copy", code: 200)
operation CopyObject {
  input: CopyObjectInput
  output: CopyObjectOutput
  errors: [StorageError]
}

structure CopyObjectInput {
  @required bucketId: String
  @required sourceKey: String
  @required destinationKey: String
  destinationBucket: String
}

structure CopyObjectOutput {
  @required Key: String
}

@http(method: "DELETE", uri: "/object/{bucketId}", code: 200)
operation DeleteObjects {
  input: DeleteObjectsInput
  output: DeleteObjectsOutput
  errors: [StorageError]
}

structure DeleteObjectsInput {
  @required
  @httpLabel
  bucketId: String

  @required prefixes: StringList
}

structure DeleteObjectsOutput {
  @required
  @httpPayload
  items: FileObjectList
}

list FileObjectList {
  member: FileObject
}

@http(method: "POST", uri: "/object/list/{bucketId}", code: 200)
operation ListObjects {
  input: ListObjectsInput
  output: ListObjectsOutput
  errors: [StorageError]
}

structure ListObjectsInput {
  @required
  @httpLabel
  bucketId: String

  @required prefix: String
  limit: Integer
  offset: Integer
  sortBy: SortBy
}

structure SortBy {
  column: String
  order: String
}

structure ListObjectsOutput {
  @required
  @httpPayload
  items: FileObjectList
}

@http(method: "GET", uri: "/object/info/{bucketId}/{wildcardPath+}", code: 200)
@readonly
operation GetObjectInfo {
  input: GetObjectInfoInput
  output: FileInfo
  errors: [StorageError]
}

structure GetObjectInfoInput {
  @required @httpLabel bucketId: String
  @required @httpLabel wildcardPath: String
}

@http(method: "HEAD", uri: "/object/{bucketId}/{wildcardPath+}", code: 200)
@readonly
operation HeadObject {
  input: HeadObjectInput
  errors: [StorageError]
}

structure HeadObjectInput {
  @required @httpLabel bucketId: String
  @required @httpLabel wildcardPath: String
}

@http(method: "POST", uri: "/object/sign/{bucketId}/{wildcardPath+}", code: 200)
operation CreateSignedUrl {
  input: CreateSignedUrlInput
  output: CreateSignedUrlOutput
  errors: [StorageError]
}

structure CreateSignedUrlInput {
  @required @httpLabel bucketId: String
  @required @httpLabel wildcardPath: String
  @required expiresIn: Integer
}

structure CreateSignedUrlOutput {
  @required signedURL: String
}

@http(method: "POST", uri: "/object/sign/{bucketId}", code: 200)
operation CreateSignedUrls {
  input: CreateSignedUrlsInput
  output: CreateSignedUrlsOutput
  errors: [StorageError]
}

structure CreateSignedUrlsInput {
  @required @httpLabel bucketId: String
  @required expiresIn: Integer
  @required paths: StringList
}

structure CreateSignedUrlsOutput {
  @required
  @httpPayload
  items: SignedUrlResultList
}

list SignedUrlResultList {
  member: SignedUrlResult
}

structure SignedUrlResult {
  signedURL: String
  @required path: String
  error: String
}

@http(method: "POST", uri: "/object/upload/sign/{bucketId}/{wildcardPath+}", code: 200)
operation CreateSignedUploadUrl {
  input: CreateSignedUploadUrlInput
  output: CreateSignedUploadUrlOutput
  errors: [StorageError]
}

structure CreateSignedUploadUrlInput {
  @required @httpLabel bucketId: String
  @required @httpLabel wildcardPath: String
  @httpHeader("x-upsert") upsert: String
}

structure CreateSignedUploadUrlOutput {
  @required url: String
}

// ─── Shared Shapes ─────────────────────────────────────────────────────────

structure Bucket {
  @required id: String
  @required name: String
  @required @jsonName("public") isPublic: Boolean
  file_size_limit: Long
  allowed_mime_types: StringList
  created_at: String
  updated_at: String
}

structure FileObject {
  @required name: String
  id: String
  updated_at: String
  created_at: String
  last_accessed_at: String
  metadata: FileMetadata
}

structure FileMetadata {
  eTag: String
  size: Long
  mimetype: String
  cacheControl: String
  lastModified: String
  contentLength: Long
  httpStatusCode: Integer
}

structure FileInfo {
  eTag: String
  size: Long
  mimetype: String
  cacheControl: String
  lastModified: String
  contentLength: Long
  httpStatusCode: Integer
}

@error("client")
structure StorageError {
  message: String
  error: String
  statusCode: String
}
