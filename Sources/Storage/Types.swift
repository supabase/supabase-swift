public import Foundation
public import HTTPTypes

/// Options for searching and paginating files within a bucket.
///
/// Pass a ``SearchOptions`` value to ``StorageBucket/list(path:options:)`` to control which files
/// are returned and how they are ordered.
///
/// ```swift
/// let options = SearchOptions(
///   limit: 50,
///   offset: 0,
///   sortBy: SortBy(column: "created_at", order: .descending),
///   search: "avatar"
/// )
/// let files = try await storage.from("avatars").list(options: options)
/// ```
///
/// ## Topics
///
/// ### Creating search options
///
/// - ``init(limit:offset:sortBy:search:)``
///
/// ### Filter and sort properties
///
/// - ``limit``
/// - ``offset``
/// - ``sortBy``
/// - ``search``
public struct SearchOptions: Encodable, Sendable {
  var prefix: String

  /// Maximum number of files to return. Defaults to `100`.
  public var limit: Int?

  /// Zero-based offset used for paginating results. Defaults to `0`.
  public var offset: Int?

  /// The column and direction to sort results by. Can be any column inside a ``StorageObject``.
  public var sortBy: SortBy?

  /// A substring filter applied to file names.
  public var search: String?

  /// Creates a ``SearchOptions`` value.
  ///
  /// - Parameters:
  ///   - limit: Maximum number of files to return.
  ///   - offset: Zero-based offset for pagination.
  ///   - sortBy: Column and direction to sort by.
  ///   - search: A substring filter applied to file names.
  public init(
    limit: Int? = nil,
    offset: Int? = nil,
    sortBy: SortBy? = nil,
    search: String? = nil
  ) {
    prefix = ""
    self.limit = limit
    self.offset = offset
    self.sortBy = sortBy
    self.search = search
  }
}

/// A column-and-direction pair used to sort ``StorageBucket/list(path:options:)`` results.
///
/// ```swift
/// SortBy(column: "name", order: .ascending)
/// SortBy(column: "created_at", order: .descending)
/// ```
///
/// ## Topics
///
/// ### Properties
///
/// - ``column``
/// - ``order``
public struct SortBy: Encodable, Sendable {
  /// The name of the column to sort by, e.g. `"name"` or `"created_at"`.
  public var column: String?

  /// The sort direction.
  public var order: SortOrder?

  /// Creates a ``SortBy`` value.
  ///
  /// - Parameters:
  ///   - column: The column name to sort by.
  ///   - order: The sort direction. Use ``SortOrder/ascending`` or ``SortOrder/descending``.
  public init(column: String? = nil, order: SortOrder? = nil) {
    self.column = column
    self.order = order
  }
}

/// Options applied when uploading or updating a file.
///
/// ```swift
/// let options = UploadOptions(
///   contentType: "image/png",
///   cacheControl: .maxAge(.seconds(86400)),
///   upsert: true
/// )
/// try await storage.from("avatars").upload(path: "user123.png", data: imageData, options: options)
/// ```
///
/// ## Topics
///
/// ### Creating upload options
///
/// - ``init(contentType:cacheControl:upsert:metadata:headers:)``
///
/// ### Upload configuration
///
/// - ``contentType``
/// - ``cacheControl``
/// - ``upsert``
/// - ``metadata``
/// - ``headers``
public struct UploadOptions: Sendable {
  /// The `Content-Type` header value, e.g. `"image/png"`. When `nil`, the type is inferred from
  /// the file extension.
  public var contentType: String?

  /// The `Cache-Control` header stored with the object and sent back on every download.
  /// Defaults to one hour, ``CacheControl/maxAge(_:)`` with `.seconds(3600)`.
  public var cacheControl: CacheControl

  /// When `true`, ``StorageBucket/upload(path:data:options:)`` overwrites an existing file at the
  /// same path. When `false` (the default), it throws ``StorageError/Code/keyAlreadyExists``.
  ///
  /// ``StorageBucket/update(path:data:options:)`` always overwrites and ignores this flag, and
  /// ``StorageBucket/uploadToSignedURL(path:token:data:options:)`` takes it from the token.
  public var upsert: Bool

  /// Arbitrary key-value metadata to attach to the uploaded object. You can later use this to
  /// filter or search for files.
  public var metadata: [String: JSONValue]?

  /// Extra HTTP headers to include with the upload request. A header set here wins over the one
  /// the SDK would send for the same name.
  public var headers: HTTPFields

  /// Creates an ``UploadOptions`` value.
  ///
  /// - Parameters:
  ///   - contentType: MIME type for the `Content-Type` header. Inferred from the extension when `nil`.
  ///   - cacheControl: The `Cache-Control` header to store with the object. Defaults to one hour.
  ///   - upsert: Whether to overwrite an existing file. Defaults to `false`.
  ///   - metadata: Arbitrary metadata key-value pairs to attach to the object.
  ///   - headers: Extra HTTP headers for the upload request.
  public init(
    contentType: String? = nil,
    cacheControl: CacheControl = .maxAge(.seconds(3600)),
    upsert: Bool = false,
    metadata: [String: JSONValue]? = nil,
    headers: HTTPFields = [:]
  ) {
    self.contentType = contentType
    self.cacheControl = cacheControl
    self.upsert = upsert
    self.metadata = metadata
    self.headers = headers
  }
}

/// A `Cache-Control` header value, stored with an object at upload and sent back on every
/// download.
///
/// Storage keeps the value verbatim, so any directive the HTTP spec allows works. Use the
/// static members for the common ones, or a string literal for anything else:
///
/// ```swift
/// UploadOptions(cacheControl: .maxAge(.seconds(86400)))
/// UploadOptions(cacheControl: .noCache)
/// UploadOptions(cacheControl: "max-age=60, s-maxage=3600")
/// ```
///
/// ## Topics
///
/// ### Common directives
///
/// - ``maxAge(_:)``
/// - ``noCache``
/// - ``noStore``
public struct CacheControl: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  /// The header value as sent, e.g. `"max-age=3600"`.
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// `max-age=N`: cache for `duration`, rounded down to whole seconds.
  public static func maxAge(_ duration: Duration) -> CacheControl {
    CacheControl(rawValue: "max-age=\(duration.components.seconds)")
  }

  /// `no-cache`: revalidate with Storage before every use.
  public static let noCache: CacheControl = "no-cache"

  /// `no-store`: never cache.
  public static let noStore: CacheControl = "no-store"
}

/// A single signed URL returned as part of a batch sign operation.
///
/// Returned by ``StorageBucket/createSignedURLs(paths:expiresIn:download:cacheNonce:)-(_,_,DownloadBehavior?,_)``
/// (the legacy `[SignedURL]` overload). Prefer the ``SignedURLResult`` overload for new code.
///
/// ## Topics
///
/// ### Properties
///
/// - ``error``
/// - ``signedURL``
/// - ``path``
public struct SignedURL: Decodable, Sendable {
  /// An optional error message. Non-nil when the path could not be signed.
  public var error: String?

  /// The signed URL.
  public var signedURL: URL

  /// The requested file path.
  public var path: String

  /// Creates a ``SignedURL``.
  ///
  /// - Parameters:
  ///   - error: An optional error message when signing failed.
  ///   - signedURL: The resulting signed URL.
  ///   - path: The requested file path.
  public init(error: String? = nil, signedURL: URL, path: String) {
    self.error = error
    self.signedURL = signedURL
    self.path = path
  }
}

/// Represents the per-item result of a ``StorageBucket/createSignedURLs(paths:expiresIn:download:cacheNonce:)-(_,_,DownloadBehavior?,_)`` call.
///
/// It is guaranteed that exactly one case applies per item: either the URL was signed
/// successfully, or the path did not exist or was inaccessible.
///
/// ```swift
/// let results = try await storage.from("docs").createSignedURLs(paths: paths, expiresIn: .seconds(3600))
/// for result in results {
///   switch result {
///   case .success(let path, let url): print(path, url)
///   case .failure(let path, let error): print(path, "failed:", error)
///   }
/// }
/// ```
///
/// ## Topics
///
/// ### Cases
///
/// - ``success(path:signedURL:)``
/// - ``failure(path:error:)``
///
/// ### Convenience accessors
///
/// - ``path``
/// - ``signedURL``
/// - ``error``
public enum SignedURLResult: Sendable {
  /// The URL was signed successfully.
  ///
  /// - Parameters:
  ///   - path: The requested file path.
  ///   - signedURL: The signed URL ready for use.
  case success(path: String, signedURL: URL)

  /// The path could not be signed.
  ///
  /// - Parameters:
  ///   - path: The requested file path.
  ///   - error: The reason the URL could not be created.
  case failure(path: String, error: String)

  /// The requested file path, available regardless of outcome.
  public var path: String {
    switch self {
    case .success(let path, _): return path
    case .failure(let path, _): return path
    }
  }

  /// The signed URL, or `nil` if this result is a failure.
  public var signedURL: URL? {
    if case .success(_, let url) = self { return url }
    return nil
  }

  /// The error message, or `nil` if this result is a success.
  public var error: String? {
    if case .failure(_, let error) = self { return error }
    return nil
  }
}

/// A signed upload URL created by ``StorageBucket/createSignedUploadURL(path:options:)``.
///
/// Pass ``token`` to ``StorageBucket/uploadToSignedURL(path:token:data:options:)`` to perform the
/// authenticated upload.
///
/// ## Topics
///
/// ### Properties
///
/// - ``signedURL``
/// - ``path``
/// - ``token``
public struct SignedUploadURL: Sendable {
  /// The fully constructed signed upload URL.
  public let signedURL: URL

  /// The destination file path within the bucket.
  public let path: String

  /// The upload authentication token extracted from ``signedURL``.
  public let token: String
}

/// The object an upload, update, or signed-URL upload created.
///
/// ## Topics
///
/// ### Properties
///
/// - ``id``
/// - ``path``
/// - ``fullPath``
public struct UploadedObject: Hashable, Sendable {
  /// The unique identifier assigned to the object. `nil` after a signed-URL upload, which
  /// Storage answers without one.
  public let id: UUID?

  /// The normalized file path within the bucket, as provided to the upload call.
  public let path: String

  /// The full storage key including the bucket name, e.g. `"avatars/user123.png"`.
  public let fullPath: String

  /// Creates an ``UploadedObject``.
  ///
  /// - Parameters:
  ///   - id: The object identifier, when Storage returned one.
  ///   - path: The file path within the bucket.
  ///   - fullPath: The full storage key including the bucket name.
  public init(id: UUID? = nil, path: String, fullPath: String) {
    self.id = id
    self.path = path
    self.fullPath = fullPath
  }
}

/// Options for creating a signed upload URL.
///
/// Pass this to ``StorageBucket/createSignedUploadURL(path:options:)`` to control whether an
/// existing file at the destination path should be overwritten.
///
/// ## Topics
///
/// ### Properties
///
/// - ``shouldUpsert``
public struct CreateSignedUploadURLOptions: Sendable {
  /// When `true`, an existing file at the destination path is overwritten by the subsequent upload.
  public var shouldUpsert: Bool

  /// Creates a ``CreateSignedUploadURLOptions`` value.
  ///
  /// - Parameter shouldUpsert: Whether to overwrite an existing object at the destination path.
  public init(shouldUpsert: Bool) {
    self.shouldUpsert = shouldUpsert
  }
}

/// Options for specifying a destination bucket when moving or copying files.
///
/// Pass to ``StorageBucket/move(from:to:options:)`` or ``StorageBucket/copy(from:to:options:)``
/// to move or copy a file across buckets.
///
/// ## Topics
///
/// ### Properties
///
/// - ``destinationBucket``
public struct DestinationOptions: Sendable {
  /// The identifier of the destination bucket. When `nil`, the operation stays within the source bucket.
  public var destinationBucket: String?

  /// Creates a ``DestinationOptions`` value.
  ///
  /// - Parameter destinationBucket: The destination bucket identifier, or `nil` to use the same bucket.
  public init(destinationBucket: String? = nil) {
    self.destinationBucket = destinationBucket
  }
}

/// One entry of a bucket listing: a file, or a folder when listing one level at a time.
///
/// ``StorageObject`` is returned by ``StorageBucket/list(path:options:)`` and
/// ``StorageBucket/remove(paths:)``.
///
/// ## Topics
///
/// ### Identifying the object
///
/// - ``name``
/// - ``id``
/// - ``version``
/// - ``isFolder``
///
/// ### Timestamps
///
/// - ``createdAt``
/// - ``updatedAt``
/// - ``lastAccessedAt``
///
/// ### Metadata
///
/// - ``metadata``
/// - ``userMetadata``
///
/// ### Versioning
///
/// - ``isVersioned``
/// - ``isDeleteMarker``
/// - ``archivedAt``
public struct StorageObject: Identifiable, Hashable, Decodable, Sendable {
  /// The name of the file, including its extension. Relative to the listed prefix in
  /// ``StorageBucket/list(path:options:)``, the full key in ``StorageBucket/remove(paths:)``.
  public var name: String

  /// The unique identifier of this object. `nil` for a folder row.
  public var id: UUID?

  /// The version identifier of this object. `nil` for a folder row and on older servers.
  public var version: String?

  /// The date and time the object was created.
  public var createdAt: Date?

  /// The date and time the object was last updated.
  public var updatedAt: Date?

  /// The date and time the object was last accessed.
  public var lastAccessedAt: Date?

  /// What Storage recorded about the stored bytes: size, MIME type, ETag. `nil` for a folder row.
  public var metadata: ObjectMetadata?

  /// The metadata the uploader attached through ``UploadOptions/metadata``.
  public var userMetadata: [String: JSONValue]?

  /// Whether this object was created while the bucket had versioning enabled.
  public var isVersioned: Bool?

  /// Whether this entry is a delete marker rather than an object version.
  public var isDeleteMarker: Bool?

  /// The date and time this version was archived.
  public var archivedAt: Date?

  /// Whether this entry is a folder: ``StorageBucket/list(path:options:)`` lists one level, and
  /// a folder arrives as a row with no ``id``.
  public var isFolder: Bool { id == nil }

  /// Creates a ``StorageObject``.
  public init(
    name: String,
    id: UUID? = nil,
    version: String? = nil,
    createdAt: Date? = nil,
    updatedAt: Date? = nil,
    lastAccessedAt: Date? = nil,
    metadata: ObjectMetadata? = nil,
    userMetadata: [String: JSONValue]? = nil,
    isVersioned: Bool? = nil,
    isDeleteMarker: Bool? = nil,
    archivedAt: Date? = nil
  ) {
    self.name = name
    self.id = id
    self.version = version
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastAccessedAt = lastAccessedAt
    self.metadata = metadata
    self.userMetadata = userMetadata
    self.isVersioned = isVersioned
    self.isDeleteMarker = isDeleteMarker
    self.archivedAt = archivedAt
  }

  enum CodingKeys: String, CodingKey {
    case name
    case id
    case version
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case lastAccessedAt = "last_accessed_at"
    case metadata
    case userMetadata = "user_metadata"
    case isVersioned = "is_versioned"
    case isDeleteMarker = "is_delete_marker"
    case archivedAt = "archived_at"
  }
}

/// What Storage recorded about an object's bytes when it was stored.
///
/// Keys Storage adds later, or that this SDK does not name, are kept in ``additional``.
///
/// ## Topics
///
/// ### Properties
///
/// - ``eTag``
/// - ``size``
/// - ``mimeType``
/// - ``cacheControl``
/// - ``lastModified``
/// - ``contentLength``
/// - ``additional``
public struct ObjectMetadata: Hashable, Decodable, Sendable {
  /// The entity tag of the stored bytes.
  public var eTag: String?

  /// The size in bytes.
  public var size: Int64?

  /// The MIME type, as sent in `Content-Type` at upload.
  public var mimeType: String?

  /// The `Cache-Control` header stored with the object.
  public var cacheControl: String?

  /// When the bytes were last written.
  public var lastModified: Date?

  /// The `Content-Length` recorded at upload, usually equal to ``size``.
  public var contentLength: Int64?

  /// Every other key Storage sent, by its wire name.
  public var additional: [String: JSONValue]

  /// Creates an ``ObjectMetadata``.
  public init(
    eTag: String? = nil,
    size: Int64? = nil,
    mimeType: String? = nil,
    cacheControl: String? = nil,
    lastModified: Date? = nil,
    contentLength: Int64? = nil,
    additional: [String: JSONValue] = [:]
  ) {
    self.eTag = eTag
    self.size = size
    self.mimeType = mimeType
    self.cacheControl = cacheControl
    self.lastModified = lastModified
    self.contentLength = contentLength
    self.additional = additional
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case eTag
    case size
    case mimeType = "mimetype"
    case cacheControl
    case lastModified
    case contentLength
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    eTag = try container.decodeIfPresent(String.self, forKey: .eTag)
    size = try container.decodeIfPresent(Int64.self, forKey: .size)
    mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
    cacheControl = try container.decodeIfPresent(String.self, forKey: .cacheControl)
    lastModified = try container.decodeIfPresent(String.self, forKey: .lastModified)?.date
    contentLength = try container.decodeIfPresent(Int64.self, forKey: .contentLength)

    let known = Set(CodingKeys.allCases.map(\.rawValue))
    let all = try decoder.singleValueContainer().decode([String: JSONValue].self)
    additional = all.filter { !known.contains($0.key) }
  }
}

/// Everything Storage knows about one object, returned by ``StorageBucket/info(path:)``.
///
/// ## Topics
///
/// ### Identifying the object
///
/// - ``id``
/// - ``version``
/// - ``name``
/// - ``bucketId``
///
/// ### Size and content type
///
/// - ``size``
/// - ``contentType``
/// - ``cacheControl``
/// - ``eTag``
///
/// ### Timestamps
///
/// - ``createdAt``
/// - ``updatedAt``
/// - ``lastAccessedAt``
/// - ``lastModified``
///
/// ### Metadata and versioning
///
/// - ``userMetadata``
/// - ``isVersioned``
/// - ``isDeleteMarker``
/// - ``archivedAt``
public struct ObjectInfo: Identifiable, Hashable, Decodable, Sendable {
  /// The unique identifier of this object.
  public var id: UUID

  /// The version identifier of this object.
  public var version: String

  /// The full key of the object within its bucket.
  public var name: String

  /// The identifier of the bucket that contains this object.
  public var bucketId: String?

  /// The size in bytes.
  public var size: Int64?

  /// The MIME type, as sent in `Content-Type` at upload.
  public var contentType: String?

  /// The `Cache-Control` header stored with the object.
  public var cacheControl: String?

  /// The entity tag of the stored bytes.
  public var eTag: String?

  /// When the bytes were last written.
  public var lastModified: Date?

  /// The date and time the object was created.
  public var createdAt: Date?

  /// The date and time the object row was last updated.
  public var updatedAt: Date?

  /// The date and time the object was last accessed.
  public var lastAccessedAt: Date?

  /// The metadata the uploader attached through ``UploadOptions/metadata``.
  public var userMetadata: [String: JSONValue]?

  /// Whether this object was created while the bucket had versioning enabled.
  public var isVersioned: Bool?

  /// Whether this entry is a delete marker rather than an object version.
  public var isDeleteMarker: Bool?

  /// The date and time this version was archived.
  public var archivedAt: Date?

  /// Creates an ``ObjectInfo``.
  public init(
    id: UUID,
    version: String,
    name: String,
    bucketId: String? = nil,
    size: Int64? = nil,
    contentType: String? = nil,
    cacheControl: String? = nil,
    eTag: String? = nil,
    lastModified: Date? = nil,
    createdAt: Date? = nil,
    updatedAt: Date? = nil,
    lastAccessedAt: Date? = nil,
    userMetadata: [String: JSONValue]? = nil,
    isVersioned: Bool? = nil,
    isDeleteMarker: Bool? = nil,
    archivedAt: Date? = nil
  ) {
    self.id = id
    self.version = version
    self.name = name
    self.bucketId = bucketId
    self.size = size
    self.contentType = contentType
    self.cacheControl = cacheControl
    self.eTag = eTag
    self.lastModified = lastModified
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastAccessedAt = lastAccessedAt
    self.userMetadata = userMetadata
    self.isVersioned = isVersioned
    self.isDeleteMarker = isDeleteMarker
    self.archivedAt = archivedAt
  }

  enum CodingKeys: String, CodingKey {
    case id
    case version
    case name
    case bucketId = "bucket_id"
    case size
    case contentType = "content_type"
    case cacheControl = "cache_control"
    case eTag = "etag"
    case lastModified = "last_modified"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case lastAccessedAt = "last_accessed_at"
    case userMetadata = "metadata"
    case isVersioned = "is_versioned"
    case isDeleteMarker = "is_delete_marker"
    case archivedAt = "archived_at"
  }
}

/// A Supabase Storage bucket.
///
/// Buckets are the top-level containers for files. Retrieve bucket details with
/// ``StorageClient/bucket(_:)`` or ``StorageClient/listBuckets()``.
///
/// ## Topics
///
/// ### Identifying the bucket
///
/// - ``id``
/// - ``name``
/// - ``owner``
///
/// ### Access and limits
///
/// - ``isPublic``
/// - ``allowedMimeTypes``
/// - ``fileSizeLimit``
///
/// ### Timestamps
///
/// - ``createdAt``
/// - ``updatedAt``
public struct Bucket: Identifiable, Hashable, Decodable, Sendable {
  /// The unique identifier of the bucket.
  public var id: String

  /// The human-readable name of the bucket.
  public var name: String

  /// The user ID of the bucket owner.
  public var owner: String

  /// Whether the bucket is publicly accessible without an authorization token.
  public var isPublic: Bool

  /// The date and time the bucket was created.
  public var createdAt: Date

  /// The date and time the bucket was last updated.
  public var updatedAt: Date

  /// MIME types accepted during upload, e.g. `["image/png", "image/*"]`. `nil` allows all types.
  public var allowedMimeTypes: [String]?

  /// Maximum file size allowed for uploads to this bucket, in bytes.
  public var fileSizeLimit: Int64?

  /// Creates a ``Bucket``.
  ///
  /// - Parameters:
  ///   - id: Unique bucket identifier.
  ///   - name: Human-readable bucket name.
  ///   - owner: User ID of the bucket owner.
  ///   - isPublic: Whether the bucket is publicly readable.
  ///   - createdAt: Creation timestamp.
  ///   - updatedAt: Last-updated timestamp.
  ///   - allowedMimeTypes: Permitted MIME types for uploads. `nil` allows all types.
  ///   - fileSizeLimit: Maximum upload size in bytes. `nil` means no limit.
  public init(
    id: String,
    name: String,
    owner: String,
    isPublic: Bool,
    createdAt: Date,
    updatedAt: Date,
    allowedMimeTypes: [String]? = nil,
    fileSizeLimit: Int64? = nil
  ) {
    self.id = id
    self.name = name
    self.owner = owner
    self.isPublic = isPublic
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.allowedMimeTypes = allowedMimeTypes
    self.fileSizeLimit = fileSizeLimit
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case owner
    case isPublic = "public"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case allowedMimeTypes = "allowed_mime_types"
    case fileSizeLimit = "file_size_limit"
  }
}

// MARK: - StorageByteCount

/// A file size limit for a Storage bucket, expressed as an integer byte count or a human-readable string.
///
/// ``StorageByteCount`` is accepted wherever a file-size limit is required (e.g. ``BucketOptions``).
/// You can create instances using the static factory methods, integer literals, or string literals.
///
/// ```swift
/// BucketOptions(fileSizeLimit: .megabytes(1.5))
/// BucketOptions(fileSizeLimit: "500kb")
/// BucketOptions(fileSizeLimit: 5_000_000)
/// ```
///
/// ## Topics
///
/// ### Creating a byte count
///
/// - ``init(_:)``
/// - ``init(stringValue:)``
/// - ``kilobytes(_:)``
/// - ``megabytes(_:)``
/// - ``gigabytes(_:)``
///
/// ### Accessing the stored value
///
/// - ``intValue``
/// - ``stringValue``
public struct StorageByteCount: Sendable, Hashable {
  /// The exact byte count, or `nil` when a human-readable string value is used.
  public let intValue: Int64?

  /// A human-readable size string (e.g. `"1.5mb"`, `"500kb"`), or `nil` when an integer is used.
  public let stringValue: String?

  /// Creates a ``StorageByteCount`` from an exact byte count.
  ///
  /// - Parameter intValue: The number of bytes.
  public init(_ intValue: Int64) {
    self.intValue = intValue
    self.stringValue = nil
  }

  /// Creates a ``StorageByteCount`` from a human-readable size string.
  ///
  /// - Parameter stringValue: A size string such as `"500kb"`, `"1.5mb"`, or `"2gb"`.
  public init(stringValue: String) {
    self.intValue = nil
    self.stringValue = stringValue
  }

  private static func formatValue(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0
      ? Int64(exactly: value).map(String.init) ?? String(value)
      : String(value)
  }

  /// Creates a ``StorageByteCount`` from a number of kilobytes.
  ///
  /// - Parameter value: Size in kilobytes.
  public static func kilobytes(_ value: Double) -> Self {
    Self(stringValue: "\(formatValue(value))kb")
  }

  /// Creates a ``StorageByteCount`` from a number of megabytes.
  ///
  /// - Parameter value: Size in megabytes.
  public static func megabytes(_ value: Double) -> Self {
    Self(stringValue: "\(formatValue(value))mb")
  }

  /// Creates a ``StorageByteCount`` from a number of gigabytes.
  ///
  /// - Parameter value: Size in gigabytes.
  public static func gigabytes(_ value: Double) -> Self {
    Self(stringValue: "\(formatValue(value))gb")
  }
}

extension StorageByteCount: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int64) { self.init(value) }
}

extension StorageByteCount: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    if let n = Int64(value) {
      self.init(n)
    } else {
      self.init(stringValue: value)
    }
  }
}

extension StorageByteCount: Encodable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    if let string = stringValue {
      try container.encode(string)
    } else {
      try container.encode(intValue ?? 0)
    }
  }
}

// MARK: - ResizeMode

/// The strategy used to fit an image into the requested dimensions during server-side transformation.
///
/// ```swift
/// ImageTransform(resize: .cover)
/// ```
///
/// ## Topics
///
/// ### Predefined modes
///
/// - ``cover``
/// - ``contain``
/// - ``fill``
public struct ResizeMode: RawRepresentable, Hashable, Sendable {
  /// The raw string value sent to the API.
  public let rawValue: String

  /// Creates a ``ResizeMode`` from a raw string value.
  ///
  /// - Parameter rawValue: The resize mode string understood by the Storage image API.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Crops the image to fill the target dimensions while preserving the aspect ratio.
  public static let cover = ResizeMode(rawValue: "cover")

  /// Scales the image to fit within the target dimensions while preserving the aspect ratio, adding
  /// letterboxing if necessary.
  public static let contain = ResizeMode(rawValue: "contain")

  /// Stretches the image to fill the target dimensions, ignoring the aspect ratio.
  public static let fill = ResizeMode(rawValue: "fill")
}

extension ResizeMode: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

// MARK: - ImageFormat

/// The output image format produced by the server-side image transformation pipeline.
///
/// ```swift
/// ImageTransform(format: .webp)
/// ```
///
/// ## Topics
///
/// ### Predefined formats
///
/// - ``origin``
/// - ``webp``
/// - ``avif``
public struct ImageFormat: RawRepresentable, Hashable, Sendable {
  /// The raw string value sent to the API.
  public let rawValue: String

  /// Creates an ``ImageFormat`` from a raw string value.
  ///
  /// - Parameter rawValue: The format string understood by the Storage image API.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Returns the image in its original format without re-encoding.
  public static let origin = ImageFormat(rawValue: "origin")

  /// Encodes the image as WebP, which typically offers better compression than JPEG or PNG.
  public static let webp = ImageFormat(rawValue: "webp")

  /// Encodes the image as AVIF for superior compression at equivalent quality.
  public static let avif = ImageFormat(rawValue: "avif")
}

extension ImageFormat: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

// MARK: - SortOrder

/// Sort direction for ``StorageBucket/list(path:options:)`` results.
///
/// ```swift
/// SortBy(column: "name", order: .ascending)
/// ```
///
/// ## Topics
///
/// ### Predefined orders
///
/// - ``ascending``
/// - ``descending``
public struct SortOrder: RawRepresentable, Hashable, Sendable {
  /// The raw string value sent to the API (`"asc"` or `"desc"`).
  public let rawValue: String

  /// Creates a ``SortOrder`` from a raw string value.
  ///
  /// - Parameter rawValue: The sort direction string (`"asc"` or `"desc"`).
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Sort results in ascending order (A → Z, oldest → newest).
  public static let ascending = SortOrder(rawValue: "asc")

  /// Sort results in descending order (Z → A, newest → oldest).
  public static let descending = SortOrder(rawValue: "desc")
}

extension SortOrder: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension SortOrder: Encodable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

// MARK: - DownloadBehavior

/// Controls the `Content-Disposition` header behavior for signed and public URLs.
///
/// ```swift
/// storage.from("docs").publicURL(path: "report.pdf", download: .withOriginalName)
/// storage.from("docs").publicURL(path: "report.pdf", download: .named("annual-2024.pdf"))
/// ```
///
/// ## Topics
///
/// ### Cases
///
/// - ``withOriginalName``
/// - ``named(_:)``
public enum DownloadBehavior: Sendable {
  /// Triggers a download using the file's original name.
  case withOriginalName

  /// Triggers a download using a custom filename.
  ///
  /// - Parameter _: The filename to suggest when saving the file.
  case named(String)

  var queryValue: String {
    switch self {
    case .withOriginalName: return ""
    case .named(let name): return name
    }
  }
}

// MARK: - BucketOptions

/// Options used when creating or updating a Storage bucket.
///
/// ```swift
/// try await storage.createBucket(
///   "user-uploads",
///   options: BucketOptions(
///     isPublic: false,
///     fileSizeLimit: .megabytes(10),
///     allowedMimeTypes: ["image/png", "image/jpeg"]
///   )
/// )
/// ```
///
/// ## Topics
///
/// ### Creating bucket options
///
/// - ``init(isPublic:fileSizeLimit:allowedMimeTypes:)``
///
/// ### Bucket settings
///
/// - ``isPublic``
/// - ``fileSizeLimit``
/// - ``allowedMimeTypes``
public struct BucketOptions: Sendable {
  /// Whether the bucket is publicly accessible without an authorization token.
  public var isPublic: Bool

  /// Maximum file size allowed for uploads, stored as a string for the API (e.g. `"10mb"`).
  public var fileSizeLimit: String?

  /// MIME types accepted during upload, e.g. `["image/png", "image/*"]`. `nil` allows all types.
  public var allowedMimeTypes: [String]?

  /// Creates a ``BucketOptions`` value.
  ///
  /// - Parameters:
  ///   - isPublic: Whether the bucket is publicly readable. Defaults to `false`.
  ///   - fileSizeLimit: Maximum upload size. Use ``StorageByteCount`` factory methods for
  ///     convenience, e.g. `.megabytes(10)`. Defaults to `nil` (no limit).
  ///   - allowedMimeTypes: Permitted MIME types. `nil` allows all MIME types.
  public init(
    isPublic: Bool = false,
    fileSizeLimit: StorageByteCount? = nil,
    allowedMimeTypes: [String]? = nil
  ) {
    self.isPublic = isPublic
    self.fileSizeLimit = fileSizeLimit?.stringValue ?? fileSizeLimit?.intValue.map(String.init)
    self.allowedMimeTypes = allowedMimeTypes
  }
}

// MARK: - ImageTransform

/// A server-side image transformation applied before the asset is served.
///
/// Pass an ``ImageTransform`` as the `transform:` argument of
/// ``StorageBucket/download(path:transform:query:cacheNonce:)``,
/// ``StorageBucket/publicURL(path:download:transform:cacheNonce:)-(_,DownloadBehavior?,_,_)`` or
/// ``StorageBucket/createSignedURL(path:expiresIn:download:transform:cacheNonce:)-(_,_,DownloadBehavior?,_,_)``
/// to resize, crop, reformat, or adjust the quality of an image on the fly.
///
/// ```swift
/// let transform = ImageTransform(width: 200, height: 200, resize: .cover, quality: 80)
/// let data = try await storage.from("avatars").download(path: "user.png", transform: transform)
/// ```
///
/// ## Topics
///
/// ### Creating a transform
///
/// - ``init(width:height:resize:quality:format:gravity:focalPoint:)``
///
/// ### Dimensions and format
///
/// - ``width``
/// - ``height``
/// - ``resize``
/// - ``quality``
/// - ``format``
///
/// ### Cropping
///
/// - ``gravity``
/// - ``focalPoint``
public struct ImageTransform: Hashable, Sendable {
  /// Target width in pixels.
  public var width: Int?

  /// Target height in pixels.
  public var height: Int?

  /// How the image is resized to fit the target dimensions. Defaults to ``ResizeMode/cover``.
  public var resize: ResizeMode?

  /// Output quality, from 20 to 100. Higher values produce larger files. Defaults to 80.
  public var quality: Int?

  /// Output image format. Defaults to the source format.
  public var format: ImageFormat?

  /// Which part of the image to keep when ``resize`` is ``ResizeMode/cover`` crops it.
  /// Defaults to ``Gravity/center``.
  public var gravity: Gravity?

  /// The point to keep when ``gravity`` is ``Gravity/focalPoint``.
  public var focalPoint: FocalPoint?

  /// Creates an ``ImageTransform``.
  ///
  /// - Parameters:
  ///   - width: Target width in pixels.
  ///   - height: Target height in pixels.
  ///   - resize: Resize strategy. Defaults to ``ResizeMode/cover`` when `nil`.
  ///   - quality: Output quality from 20–100. Defaults to 80 when `nil`.
  ///   - format: Output image format. Defaults to the source format when `nil`.
  ///   - gravity: Which part of the image a cover crop keeps. Defaults to the center when `nil`.
  ///   - focalPoint: The point a ``Gravity/focalPoint`` crop keeps.
  public init(
    width: Int? = nil,
    height: Int? = nil,
    resize: ResizeMode? = nil,
    quality: Int? = nil,
    format: ImageFormat? = nil,
    gravity: Gravity? = nil,
    focalPoint: FocalPoint? = nil
  ) {
    self.width = width
    self.height = height
    self.resize = resize
    self.quality = quality
    self.format = format
    self.gravity = gravity
    self.focalPoint = focalPoint
  }

  var isEmpty: Bool {
    queryItems.isEmpty
  }

  /// The transform as the `render` routes read it from the query string.
  var queryItems: [URLQueryItem] {
    var items = [URLQueryItem]()

    if let width {
      items.append(URLQueryItem(name: "width", value: String(width)))
    }

    if let height {
      items.append(URLQueryItem(name: "height", value: String(height)))
    }

    if let resize {
      items.append(URLQueryItem(name: "resize", value: resize.rawValue))
    }

    if let quality {
      items.append(URLQueryItem(name: "quality", value: String(quality)))
    }

    if let format {
      items.append(URLQueryItem(name: "format", value: format.rawValue))
    }

    if let gravity {
      items.append(URLQueryItem(name: "gravity", value: gravity.rawValue))
    }

    if let focalPoint {
      items.append(URLQueryItem(name: "x_offset", value: focalPoint.x.description))
      items.append(URLQueryItem(name: "y_offset", value: focalPoint.y.description))
    }

    return items
  }

  /// The transform as the sign route reads it from the request body.
  struct Body: Encodable {
    let width: Int?
    let height: Int?
    let resize: String?
    let quality: Int?
    let format: String?
    let gravity: String?
    let xOffset: Double?
    let yOffset: Double?

    enum CodingKeys: String, CodingKey {
      case width, height, resize, quality, format, gravity
      case xOffset = "x_offset"
      case yOffset = "y_offset"
    }
  }

  var body: Body {
    Body(
      width: width, height: height, resize: resize?.rawValue, quality: quality,
      format: format?.rawValue, gravity: gravity?.rawValue, xOffset: focalPoint?.x,
      yOffset: focalPoint?.y)
  }
}

// MARK: - Gravity

/// Which part of an image a ``ResizeMode/cover`` crop keeps.
///
/// ```swift
/// ImageTransform(width: 200, height: 200, resize: .cover, gravity: .north)
/// ImageTransform(width: 200, height: 200, gravity: .focalPoint, focalPoint: .init(x: 0.3, y: 0.7))
/// ```
///
/// ## Topics
///
/// ### Edges and corners
///
/// - ``north``
/// - ``south``
/// - ``east``
/// - ``west``
/// - ``northEast``
/// - ``northWest``
/// - ``southEast``
/// - ``southWest``
///
/// ### Content-based
///
/// - ``center``
/// - ``smart``
/// - ``focalPoint``
public struct Gravity: RawRepresentable, Hashable, Sendable {
  /// The raw string value sent to the API.
  public let rawValue: String

  /// Creates a ``Gravity`` from a raw string value.
  ///
  /// - Parameter rawValue: The gravity string understood by the Storage image API.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Keep the top edge.
  public static let north = Gravity(rawValue: "no")

  /// Keep the bottom edge.
  public static let south = Gravity(rawValue: "so")

  /// Keep the right edge.
  public static let east = Gravity(rawValue: "ea")

  /// Keep the left edge.
  public static let west = Gravity(rawValue: "we")

  /// Keep the top-right corner.
  public static let northEast = Gravity(rawValue: "noea")

  /// Keep the top-left corner.
  public static let northWest = Gravity(rawValue: "nowe")

  /// Keep the bottom-right corner.
  public static let southEast = Gravity(rawValue: "soea")

  /// Keep the bottom-left corner.
  public static let southWest = Gravity(rawValue: "sowe")

  /// Keep the center. The default.
  public static let center = Gravity(rawValue: "ce")

  /// Let the server pick the most interesting region.
  public static let smart = Gravity(rawValue: "sm")

  /// Keep the point given by ``ImageTransform/focalPoint``.
  public static let focalPoint = Gravity(rawValue: "fp")
}

extension Gravity: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

// MARK: - FocalPoint

/// The point of an image a ``Gravity/focalPoint`` crop keeps, as fractions of the width and
/// height from the top-left corner, each in `0...1`.
public struct FocalPoint: Hashable, Sendable {
  /// Horizontal position, `0` at the left edge and `1` at the right edge.
  public var x: Double

  /// Vertical position, `0` at the top edge and `1` at the bottom edge.
  public var y: Double

  /// Creates a ``FocalPoint``.
  ///
  /// - Parameters:
  ///   - x: Horizontal position in `0...1`.
  ///   - y: Vertical position in `0...1`.
  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}
