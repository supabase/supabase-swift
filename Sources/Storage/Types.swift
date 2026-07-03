import Foundation

/// Options for searching and paginating files within a bucket.
///
/// Pass a ``SearchOptions`` value to ``StorageFileApi/list(path:options:)`` to control which files
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

  /// The column and direction to sort results by. Can be any column inside a ``FileObject``.
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

/// A column-and-direction pair used to sort ``StorageFileApi/list(path:options:)`` results.
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

  /// The raw sort direction string (`"asc"` or `"desc"`).
  public var order: String?

  /// Creates a ``SortBy`` value.
  ///
  /// - Parameters:
  ///   - column: The column name to sort by.
  ///   - order: The sort direction. Use ``SortOrder/ascending`` or ``SortOrder/descending``.
  public init(column: String? = nil, order: SortOrder? = nil) {
    self.column = column
    self.order = order?.rawValue
  }
}

/// Options applied when uploading or updating a file.
///
/// ```swift
/// let options = FileOptions(
///   cacheControl: "86400",
///   contentType: "image/png",
///   upsert: true
/// )
/// try await storage.from("avatars").upload("user123.png", data: imageData, options: options)
/// ```
///
/// ## Topics
///
/// ### Creating file options
///
/// - ``init(cacheControl:contentType:upsert:duplex:metadata:headers:)``
///
/// ### Upload configuration
///
/// - ``cacheControl``
/// - ``contentType``
/// - ``upsert``
/// - ``duplex``
/// - ``metadata``
/// - ``headers``
public struct FileOptions: Sendable {
  /// The number of seconds the asset is cached in the browser and in the Supabase CDN.
  ///
  /// This value is set in the `Cache-Control: max-age=<seconds>` header. Defaults to `"3600"`.
  public var cacheControl: String

  /// The `Content-Type` header value, e.g. `"image/png"`. When `nil`, the type is inferred from
  /// the file extension.
  public var contentType: String?

  /// When `true`, overwrites an existing file at the same path. When `false` (the default), an
  /// error is thrown if an object already exists at the destination path.
  public var upsert: Bool

  /// Enables or disables duplex streaming on the underlying `fetch()` call, allowing simultaneous
  /// reading and writing within the same stream.
  public var duplex: String?

  /// Arbitrary key-value metadata to attach to the uploaded object. You can later use this to
  /// filter or search for files.
  public var metadata: [String: AnyJSON]?

  /// Extra HTTP headers to include with the upload request.
  public var headers: [String: String]?

  /// Creates a ``FileOptions`` value.
  ///
  /// - Parameters:
  ///   - cacheControl: Seconds for the `Cache-Control: max-age` header. Defaults to `"3600"`.
  ///   - contentType: MIME type for the `Content-Type` header. Inferred from the extension when `nil`.
  ///   - upsert: Whether to overwrite an existing file. Defaults to `false`.
  ///   - duplex: Duplex streaming mode string, if needed.
  ///   - metadata: Arbitrary metadata key-value pairs to attach to the object.
  ///   - headers: Extra HTTP headers for the upload request.
  public init(
    cacheControl: String = "3600",
    contentType: String? = nil,
    upsert: Bool = false,
    duplex: String? = nil,
    metadata: [String: AnyJSON]? = nil,
    headers: [String: String]? = nil
  ) {
    self.cacheControl = cacheControl
    self.contentType = contentType
    self.upsert = upsert
    self.duplex = duplex
    self.metadata = metadata
    self.headers = headers
  }
}

/// A single signed URL returned as part of a batch sign operation.
///
/// Returned by ``StorageFileApi/createSignedURLs(paths:expiresIn:download:cacheNonce:)-5lkmo``
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

/// Represents the per-item result of a ``StorageFileApi/createSignedURLs(paths:expiresIn:download:cacheNonce:)`` call.
///
/// It is guaranteed that exactly one case applies per item: either the URL was signed
/// successfully, or the path did not exist or was inaccessible.
///
/// ```swift
/// let results = try await storage.from("docs").createSignedURLs(paths: paths, expiresIn: 3600)
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

/// A signed upload URL created by ``StorageFileApi/createSignedUploadURL(path:options:)``.
///
/// Pass ``token`` to ``StorageFileApi/uploadToSignedURL(_:token:data:options:)`` to perform the
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

/// The response returned after a successful file upload or update.
///
/// ## Topics
///
/// ### Properties
///
/// - ``id``
/// - ``path``
/// - ``fullPath``
public struct FileUploadResponse: Sendable {
  /// The unique identifier assigned to the uploaded object.
  public let id: String

  /// The relative file path within the bucket, as provided to the upload call.
  public let path: String

  /// The full storage key including the bucket name, e.g. `"avatars/user123.png"`.
  public let fullPath: String
}

/// The response returned after a successful upload via a signed URL.
///
/// ## Topics
///
/// ### Properties
///
/// - ``path``
/// - ``fullPath``
public struct SignedURLUploadResponse: Sendable {
  /// The relative file path within the bucket, as provided to the upload call.
  public let path: String

  /// The full storage key including the bucket name, e.g. `"avatars/user123.png"`.
  public let fullPath: String
}

/// Options for creating a signed upload URL.
///
/// Pass this to ``StorageFileApi/createSignedUploadURL(path:options:)`` to control whether an
/// existing file at the destination path should be overwritten.
///
/// ## Topics
///
/// ### Properties
///
/// - ``upsert``
public struct CreateSignedUploadURLOptions: Sendable {
  /// When `true`, an existing file at the destination path is overwritten by the subsequent upload.
  public var upsert: Bool

  /// Creates a ``CreateSignedUploadURLOptions`` value.
  ///
  /// - Parameter upsert: Whether to overwrite an existing object at the destination path.
  public init(upsert: Bool) {
    self.upsert = upsert
  }
}

/// Options for specifying a destination bucket when moving or copying files.
///
/// Pass to ``StorageFileApi/move(from:to:options:)`` or ``StorageFileApi/copy(from:to:options:)``
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

/// Metadata about a file stored in a Supabase Storage bucket.
///
/// ``FileObject`` is returned by ``StorageFileApi/list(path:options:)`` and
/// ``StorageFileApi/remove(paths:)``.
///
/// ## Topics
///
/// ### Identifying the file
///
/// - ``id``
/// - ``name``
/// - ``bucketId``
/// - ``owner``
///
/// ### Timestamps
///
/// - ``createdAt``
/// - ``updatedAt``
/// - ``lastAccessedAt``
///
/// ### Metadata and associations
///
/// - ``metadata``
/// - ``buckets``
public struct FileObject: Identifiable, Hashable, Codable, Sendable {
  /// The name of the file, including its extension.
  public var name: String

  /// The identifier of the bucket that contains this file.
  public var bucketId: String?

  /// The user ID of the file owner.
  public var owner: String?

  /// The unique identifier of this file object.
  public var id: UUID?

  /// The date and time the file was last updated.
  public var updatedAt: Date?

  /// The date and time the file was created.
  public var createdAt: Date?

  /// The date and time the file was last accessed.
  public var lastAccessedAt: Date?

  /// Arbitrary key-value metadata attached to the file at upload time.
  public var metadata: [String: AnyJSON]?

  /// The bucket associated with this file, if it was eagerly loaded.
  public var buckets: Bucket?

  /// Creates a ``FileObject``.
  ///
  /// - Parameters:
  ///   - name: The file name including its extension.
  ///   - bucketId: The bucket identifier.
  ///   - owner: The owner's user ID.
  ///   - id: The unique object identifier.
  ///   - updatedAt: Last-updated timestamp.
  ///   - createdAt: Creation timestamp.
  ///   - lastAccessedAt: Last-accessed timestamp.
  ///   - metadata: Arbitrary key-value metadata.
  ///   - buckets: The associated ``Bucket``, if available.
  public init(
    name: String,
    bucketId: String? = nil,
    owner: String? = nil,
    id: UUID? = nil,
    updatedAt: Date? = nil,
    createdAt: Date? = nil,
    lastAccessedAt: Date? = nil,
    metadata: [String: AnyJSON]? = nil,
    buckets: Bucket? = nil
  ) {
    self.name = name
    self.bucketId = bucketId
    self.owner = owner
    self.id = id
    self.updatedAt = updatedAt
    self.createdAt = createdAt
    self.lastAccessedAt = lastAccessedAt
    self.metadata = metadata
    self.buckets = buckets
  }

  enum CodingKeys: String, CodingKey {
    case name
    case bucketId = "bucket_id"
    case owner
    case id
    case updatedAt = "updated_at"
    case createdAt = "created_at"
    case lastAccessedAt = "last_accessed_at"
    case metadata
    case buckets
  }
}

/// Extended metadata about a file stored in Supabase Storage, returned by the v2 API.
///
/// ``FileObjectV2`` is returned by ``StorageFileApi/info(path:)`` and provides richer metadata
/// compared to ``FileObject``.
///
/// ## Topics
///
/// ### Identifying the file
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
/// - ``etag``
///
/// ### Timestamps
///
/// - ``createdAt``
/// - ``updatedAt``
/// - ``lastAccessedAt``
/// - ``lastModified``
///
/// ### Metadata
///
/// - ``metadata``
public struct FileObjectV2: Identifiable, Hashable, Decodable, Sendable {
  /// The unique identifier of this object.
  public let id: String

  /// The storage version string for this object.
  public let version: String

  /// The file name including its extension.
  public let name: String

  /// The identifier of the bucket that contains this file.
  public let bucketId: String?

  /// The date and time the file was last updated.
  public let updatedAt: Date?

  /// The date and time the file was created.
  public let createdAt: Date?

  /// The date and time the file was last accessed.
  public let lastAccessedAt: Date?

  /// The file size in bytes.
  public let size: Int?

  /// The `Cache-Control` header value associated with this file.
  public let cacheControl: String?

  /// The MIME content type of the file.
  public let contentType: String?

  /// The ETag of the stored object.
  public let etag: String?

  /// The date and time the object was last modified.
  public let lastModified: Date?

  /// Arbitrary key-value metadata attached to the file at upload time.
  public let metadata: [String: AnyJSON]?

  enum CodingKeys: String, CodingKey {
    case id
    case version
    case name
    case bucketId = "bucket_id"
    case updatedAt = "updated_at"
    case createdAt = "created_at"
    case lastAccessedAt = "last_accessed_at"
    case size
    case cacheControl = "cache_control"
    case contentType = "content_type"
    case etag
    case lastModified = "last_modified"
    case metadata
  }
}

/// A Supabase Storage bucket.
///
/// Buckets are the top-level containers for files. Retrieve bucket details with
/// ``StorageBucketApi/getBucket(_:)`` or ``StorageBucketApi/listBuckets()``.
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
public struct Bucket: Identifiable, Hashable, Codable, Sendable {
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
    value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int64(value)) : String(value)
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
/// TransformOptions(resize: .cover)
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

extension ResizeMode: Codable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(rawValue: try container.decode(String.self))
  }
}

// MARK: - ImageFormat

/// The output image format produced by the server-side image transformation pipeline.
///
/// ```swift
/// TransformOptions(format: .webp)
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

extension ImageFormat: Codable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(rawValue: try container.decode(String.self))
  }
}

// MARK: - SortOrder

/// Sort direction for ``StorageFileApi/list(path:options:)`` results.
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

extension SortOrder: Codable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(rawValue: try container.decode(String.self))
  }
}

// MARK: - DownloadBehavior

/// Controls the `Content-Disposition` header behaviour for signed and public URLs.
///
/// ```swift
/// storage.from("docs").getPublicURL(path: "report.pdf", download: .withOriginalName)
/// storage.from("docs").getPublicURL(path: "report.pdf", download: .named("annual-2024.pdf"))
/// ```
///
/// ## Topics
///
/// ### Cases
///
/// - ``withOriginalName``
/// - ``named(_:)``
public enum DownloadBehavior: Sendable {
  /// Triggers a browser download using the file's original name.
  case withOriginalName

  /// Triggers a browser download using a custom filename.
  ///
  /// - Parameter _: The filename the browser should suggest when saving the file.
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

// MARK: - TransformOptions

/// Options for server-side image transformation applied before the asset is served to the client.
///
/// Pass a ``TransformOptions`` value to ``StorageFileApi/download(path:options:query:cacheNonce:)``,
/// ``StorageFileApi/getPublicURL(path:download:options:cacheNonce:)``, or
/// ``StorageFileApi/createSignedURL(path:expiresIn:download:transform:cacheNonce:)`` to resize,
/// reformat, or adjust the quality of images on the fly.
///
/// ```swift
/// let options = TransformOptions(width: 200, height: 200, resize: .cover, quality: 80)
/// let data = try await storage.from("avatars").download(path: "user.png", options: options)
/// ```
///
/// ## Topics
///
/// ### Creating transform options
///
/// - ``init(width:height:resize:quality:format:)``
///
/// ### Dimensions and format
///
/// - ``width``
/// - ``height``
/// - ``resize``
/// - ``quality``
/// - ``format``
public struct TransformOptions: Encodable, Sendable {
  /// Target width in pixels.
  public var width: Int?

  /// Target height in pixels.
  public var height: Int?

  /// How the image is resized to fit the target dimensions. Defaults to `cover`.
  public var resize: String?

  /// Output quality, from 20 to 100. Higher values produce larger files. Defaults to 80.
  public var quality: Int?

  /// Output image format.
  public var format: String?

  /// Creates a ``TransformOptions`` value.
  ///
  /// - Parameters:
  ///   - width: Target width in pixels.
  ///   - height: Target height in pixels.
  ///   - resize: Resize strategy. Defaults to ``ResizeMode/cover`` when `nil`.
  ///   - quality: Output quality from 20–100. Defaults to 80 when `nil`.
  ///   - format: Output image format. Defaults to the source format when `nil`.
  public init(
    width: Int? = nil,
    height: Int? = nil,
    resize: ResizeMode? = nil,
    quality: Int? = nil,
    format: ImageFormat? = nil
  ) {
    self.width = width
    self.height = height
    self.resize = resize?.rawValue
    self.quality = quality
    self.format = format?.rawValue
  }

  var isEmpty: Bool {
    queryItems.isEmpty
  }

  var queryItems: [URLQueryItem] {
    var items = [URLQueryItem]()

    if let width {
      items.append(URLQueryItem(name: "width", value: String(width)))
    }

    if let height {
      items.append(URLQueryItem(name: "height", value: String(height)))
    }

    if let resize {
      items.append(URLQueryItem(name: "resize", value: resize))
    }

    if let quality {
      items.append(URLQueryItem(name: "quality", value: String(quality)))
    }

    if let format {
      items.append(URLQueryItem(name: "format", value: format))
    }

    return items
  }
}
