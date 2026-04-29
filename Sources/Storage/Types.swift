import Foundation

/// Parameters used to filter and paginate results from ``StorageFileAPI/list(path:options:)``.
///
/// All fields are optional; omitted fields fall back to server-side defaults (100 items per page,
/// sorted by name ascending).
///
/// ## Example
///
/// ```swift
/// // List up to 20 files inside "user-123/", sorted by creation date (newest first)
/// let files = try await storage.from("documents").list(
///   path: "user-123",
///   options: SearchOptions(
///     limit: 20,
///     offset: 0,
///     sortBy: SortBy(column: "created_at", order: "desc"),
///     search: "report"
///   )
/// )
/// ```
public struct SearchOptions: Encodable, Sendable {
  var prefix: String

  /// The maximum number of files to return. Defaults to `100` when `nil`.
  public var limit: Int?

  /// The zero-based index of the first file to return. Use together with ``limit`` to paginate
  /// results. Defaults to `0` when `nil`.
  public var offset: Int?

  /// The column and direction used to sort the results.
  ///
  /// Can reference any property exposed on ``FileObject``, e.g. `"name"`, `"created_at"`,
  /// `"updated_at"`. Defaults to ascending by `"name"` when `nil`.
  public var sortBy: SortBy?

  /// A string used to filter files whose names contain the given value.
  ///
  /// Pass `nil` (the default) to return all files within the specified path.
  public var search: String?

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

/// Defines the sort column and direction for a ``StorageFileAPI/list(path:options:)`` response.
///
/// ## Example
///
/// ```swift
/// let options = SearchOptions(sortBy: SortBy(column: "updated_at", order: "desc"))
/// ```
public struct SortBy: Encodable, Sendable {
  /// The column to sort by.
  ///
  /// Can be any field exposed in ``FileObject``, e.g. `"name"`, `"created_at"`, `"updated_at"`.
  public var column: String?

  /// The sort direction: `"asc"` for ascending or `"desc"` for descending.
  public var order: String?

  public init(column: String? = nil, order: String? = nil) {
    self.column = column
    self.order = order
  }
}

/// Options that control how a file is stored when uploading or updating it in a bucket.
///
/// Pass a `FileOptions` value to any of the upload or update methods on ``StorageFileAPI`` to
/// customise caching behaviour, content type, upsert semantics, and optional metadata.
///
/// ## Example
///
/// ```swift
/// let options = FileOptions(
///   cacheControl: "86400",        // cache for 24 hours
///   contentType: "image/jpeg",
///   upsert: true,                  // overwrite if the path already exists
///   metadata: ["userId": "abc123"]
/// )
/// try await storage.from("avatars").upload("user.jpg", data: jpegData, options: options)
/// ```
public struct FileOptions: Sendable {
  /// The number of seconds the asset is cached in the browser and in the Supabase CDN.
  ///
  /// Sets the `Cache-Control: max-age=<seconds>` response header. Defaults to `"3600"` (1 hour).
  public var cacheControl: String

  /// The MIME type of the file, sent as the `Content-Type` header.
  ///
  /// When `nil`, the MIME type is inferred from the file extension. Defaults to `nil`.
  public var contentType: String?

  /// Whether to overwrite an existing file at the same path.
  ///
  /// When `true`, any existing object at the path is silently replaced. When `false` (the
  /// default), an error is returned if the path is already occupied.
  public var upsert: Bool

  /// Enables or disables duplex streaming for the underlying fetch request.
  ///
  /// Pass `"half"` to enable half-duplex streaming. Leave `nil` (the default) for standard
  /// request behaviour.
  public var duplex: String?

  /// Arbitrary key-value metadata attached to the object in the storage backend.
  ///
  /// Values must be JSON-serialisable. The metadata can be queried and filtered through the
  /// Supabase Storage API. Defaults to `nil`.
  public var metadata: [String: AnyJSON]?

  /// Additional HTTP headers sent with the upload request.
  ///
  /// Use sparingly; most upload behaviour is controlled by the dedicated properties above.
  /// Defaults to `nil`.
  public var headers: [String: String]?

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

/// A signed URL together with its associated file path and an optional error message.
///
/// > Note: Prefer ``SignedURLResult`` for the per-item results returned by
/// > ``StorageFileAPI/createSignedURLs(paths:expiresIn:download:cacheNonce:)``.
/// > `SignedURL` is retained for backward compatibility.
public struct SignedURL: Decodable, Sendable {
  /// An error message when the signed URL could not be generated. `nil` on success.
  public var error: String?

  /// The ready-to-use signed URL.
  public var signedURL: URL

  /// The relative path of the file within the bucket.
  public var path: String

  public init(error: String? = nil, signedURL: URL, path: String) {
    self.error = error
    self.signedURL = signedURL
    self.path = path
  }
}

/// Represents the per-item result of a
/// ``StorageFileAPI/createSignedURLs(paths:expiresIn:download:cacheNonce:)`` call.
///
/// It is guaranteed that exactly one case applies per item: either the URL was signed
/// successfully, or the path did not exist / was inaccessible.
public enum SignedURLResult: Sendable {
  /// The URL was signed successfully.
  /// - Parameters:
  ///   - path: The requested file path.
  ///   - signedURL: The signed URL ready for use.
  case success(path: String, signedURL: URL)

  /// The path could not be signed.
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

/// The result of ``StorageFileAPI/createSignedUploadURL(path:options:)``.
///
/// Use ``signedURL`` to perform a multipart upload without further authentication, and pass
/// ``token`` to ``StorageFileAPI/uploadToSignedURL(_:token:data:options:)`` to complete the
/// upload.
///
/// ## Example
///
/// ```swift
/// let signed = try await storage.from("uploads").createSignedUploadURL(path: "report.pdf")
/// try await storage.from("uploads").uploadToSignedURL(
///   signed.path,
///   token: signed.token,
///   data: pdfData
/// )
/// ```
public struct SignedUploadURL: Sendable {
  /// The pre-signed URL to which the file should be uploaded.
  public let signedURL: URL

  /// The relative path within the bucket where the file will be stored.
  public let path: String

  /// The upload token embedded in ``signedURL``, extracted for convenience.
  ///
  /// Pass this value to ``StorageFileAPI/uploadToSignedURL(_:token:data:options:)`` or
  /// ``StorageFileAPI/uploadToSignedURL(_:token:fileURL:options:)`` to perform the upload.
  public let token: String
}

/// The server's response after a successful file upload or update.
///
/// Returned by ``StorageFileAPI/upload(_:data:options:)``,
/// ``StorageFileAPI/upload(_:fileURL:options:)``,
/// ``StorageFileAPI/update(_:data:options:)``, and
/// ``StorageFileAPI/update(_:fileURL:options:)``.
public struct FileUploadResponse: Sendable {
  /// The storage-object identifier assigned by Supabase.
  public let id: String

  /// The relative path supplied at upload time, e.g. `"folder/image.png"`.
  public let path: String

  /// The full storage key, including the bucket name prefix, e.g. `"avatars/folder/image.png"`.
  public let fullPath: String
}

/// The server's response after a successful upload via a signed upload URL.
///
/// Returned by ``StorageFileAPI/uploadToSignedURL(_:token:data:options:)`` and
/// ``StorageFileAPI/uploadToSignedURL(_:token:fileURL:options:)``.
public struct SignedURLUploadResponse: Sendable {
  /// The relative path within the bucket where the file was stored.
  public let path: String

  /// The full storage key, including the bucket name prefix.
  public let fullPath: String
}

/// Options for ``StorageFileAPI/createSignedUploadURL(path:options:)``.
public struct CreateSignedUploadURLOptions: Sendable {
  /// When `true`, any existing file at the target path is overwritten.
  ///
  /// Defaults to `false`, which means an error is returned if the path is already occupied.
  public var upsert: Bool

  /// Creates signed upload URL options.
  ///
  /// - Parameter upsert: Pass `true` to overwrite an existing file at the upload path.
  public init(upsert: Bool) {
    self.upsert = upsert
  }
}

/// Options that control the destination when moving or copying a file.
///
/// Pass to ``StorageFileAPI/move(from:to:options:)`` or
/// ``StorageFileAPI/copy(from:to:options:)``.
public struct DestinationOptions: Sendable {
  /// The identifier of the destination bucket.
  ///
  /// When `nil`, the operation stays within the same bucket as the source. Supply a bucket ID
  /// to move or copy a file across buckets.
  public var destinationBucket: String?

  public init(destinationBucket: String? = nil) {
    self.destinationBucket = destinationBucket
  }
}

/// Metadata for a file or folder stored in a Supabase Storage bucket.
///
/// Returned by ``StorageFileAPI/list(path:options:)`` and ``StorageFileAPI/remove(paths:)``.
/// Folders appear as `FileObject` values whose ``name`` ends with a trailing `/`.
public struct FileObject: Identifiable, Hashable, Codable, Sendable {
  /// The name of the file or folder, e.g. `"avatar.png"`.
  public var name: String

  /// The identifier of the bucket that contains this object.
  public var bucketId: String?

  /// The user ID of the object owner.
  public var owner: String?

  /// The unique identifier of the storage object, assigned by Supabase.
  public var id: UUID?

  /// When the object was last modified.
  public var updatedAt: Date?

  /// When the object was first created.
  public var createdAt: Date?

  /// When the object was last accessed.
  public var lastAccessedAt: Date?

  /// Arbitrary key-value metadata attached to the object at upload time.
  public var metadata: [String: AnyJSON]?

  /// The ``Bucket`` that contains this object.
  ///
  /// Populated only when the bucket details are joined in the query; otherwise `nil`.
  public var buckets: Bucket?

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

/// Extended metadata for a file stored in a Supabase Storage bucket.
///
/// Returned by ``StorageFileAPI/info(path:)``. Unlike ``FileObject``, this type includes
/// content-level details such as file size, ETag, and content type.
public struct FileObjectV2: Identifiable, Hashable, Decodable, Sendable {
  /// The unique storage identifier for the object.
  public let id: String

  /// The internal version string of the object, used for cache busting.
  public let version: String

  /// The name of the file, e.g. `"avatar.png"`.
  public let name: String

  /// The identifier of the bucket that contains this object.
  public let bucketId: String?

  /// When the object was last modified.
  public let updatedAt: Date?

  /// When the object was first created.
  public let createdAt: Date?

  /// When the object was last accessed.
  public let lastAccessedAt: Date?

  /// The file size in bytes.
  public let size: Int?

  /// The `Cache-Control` header value associated with the object.
  public let cacheControl: String?

  /// The MIME content type of the object (e.g. `"image/png"`).
  public let contentType: String?

  /// The ETag of the object, which can be used for conditional HTTP requests.
  public let etag: String?

  /// The `Last-Modified` date as reported by the storage server.
  public let lastModified: Date?

  /// Arbitrary key-value metadata attached to the object at upload time.
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

/// Metadata for a Supabase Storage bucket.
///
/// Returned by ``StorageClient/listBuckets()`` and ``StorageClient/getBucket(_:)``, and
/// embedded in ``FileObject/buckets`` when bucket details are joined in a list query.
public struct Bucket: Identifiable, Hashable, Codable, Sendable {
  /// The unique identifier for the bucket.
  public var id: String

  /// The human-readable display name of the bucket.
  public var name: String

  /// The user ID of the bucket owner.
  public var owner: String

  /// Whether the bucket is publicly accessible without an authorization token.
  public var isPublic: Bool

  /// When the bucket was created.
  public var createdAt: Date

  /// When the bucket was last updated.
  public var updatedAt: Date

  /// The MIME types permitted for uploads into this bucket.
  ///
  /// `nil` means all MIME types are accepted.
  public var allowedMimeTypes: [String]?

  /// The maximum file size in bytes that can be uploaded to this bucket.
  ///
  /// `nil` means the global project limit applies.
  public var fileSizeLimit: Int64?

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

/// A type-safe byte count, modelled after `Swift.Duration`.
///
/// Uses `Int64` backing to avoid the precision loss of `Measurement<UnitInformationStorage>`
/// and sidesteps the SI vs binary ambiguity of Foundation's `UnitInformationStorage`.
///
/// ## Example
///
/// ```swift
/// BucketOptions(isPublic: true, fileSizeLimit: .megabytes(5))
/// BucketOptions(isPublic: true, fileSizeLimit: .gigabytes(1))
/// BucketOptions(isPublic: true, fileSizeLimit: 5_242_880)  // raw bytes via integer literal
/// ```
public struct StorageByteCount: Sendable, Hashable {
  /// The raw byte count.
  public let bytes: Int64

  public init(_ bytes: Int64) { self.bytes = bytes }

  public static func bytes(_ value: Int64) -> Self { Self(value) }
  public static func kilobytes(_ value: Int64) -> Self { Self(value * 1_024) }
  public static func megabytes(_ value: Int64) -> Self { Self(value * 1_024 * 1_024) }
  public static func gigabytes(_ value: Int64) -> Self { Self(value * 1_024 * 1_024 * 1_024) }
}

extension StorageByteCount: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int64) { self.init(value) }
}

/// Options used when creating or updating a Storage bucket.
///
/// Pass an instance to ``StorageClient/createBucket(_:options:)`` or
/// ``StorageClient/updateBucket(_:options:)`` to configure bucket-level defaults for visibility,
/// file-size limits, and allowed MIME types.
///
/// ## Example
///
/// ```swift
/// // Create a public bucket that only accepts images up to 5 MB
/// try await storage.createBucket(
///   "avatars",
///   options: BucketOptions(
///     public: true,
///     fileSizeLimit: "5242880",
///     allowedMimeTypes: ["image/*"]
///   )
/// )
/// ```
public struct BucketOptions: Sendable {
  /// Whether the bucket is publicly accessible.
  ///
  /// Public buckets allow file downloads without an authorization token. All other operations
  /// (upload, delete, list) still require a valid token. Defaults to `false`.
  public var `public`: Bool

  /// The maximum file size allowed for uploads, expressed in bytes as a string (e.g. `"5242880"` for 5 MB).
  ///
  /// The global project file-size limit takes precedence over this value.
  /// Pass `nil` to impose no per-bucket limit (the default).
  public var fileSizeLimit: String?

  /// MIME types accepted during upload to this bucket.
  ///
  /// Each entry can be an exact MIME type (`"image/png"`) or a wildcard (`"image/*"`).
  /// Pass `nil` to allow all MIME types (the default).
  public var allowedMimeTypes: [String]?

  public init(
    public: Bool = false,
    fileSizeLimit: String? = nil,
    allowedMimeTypes: [String]? = nil
  ) {
    self.public = `public`
    self.fileSizeLimit = fileSizeLimit
    self.allowedMimeTypes = allowedMimeTypes
  }
}

/// Resize mode for on-the-fly image transformation.
///
/// Follows the `FunctionRegion` pattern: open to custom backend values without
/// requiring an SDK update.
public struct ResizeMode: RawRepresentable, Hashable, Sendable {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Fill the target dimensions, cropping any overflow. Default behaviour.
  public static let cover = ResizeMode(rawValue: "cover")
  /// Fit the image within the target dimensions, letterboxing if needed.
  public static let contain = ResizeMode(rawValue: "contain")
  /// Stretch the image to exactly fill the target dimensions.
  public static let fill = ResizeMode(rawValue: "fill")
}

extension ResizeMode: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension ResizeMode: Encodable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

extension ResizeMode: Decodable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }
}

/// Output format for on-the-fly image transformation.
///
/// Follows the `FunctionRegion` pattern: open to custom backend values.
public struct ImageFormat: RawRepresentable, Hashable, Sendable {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Preserve the original file format.
  public static let origin = ImageFormat(rawValue: "origin")
  public static let webp = ImageFormat(rawValue: "webp")
  public static let avif = ImageFormat(rawValue: "avif")
}

extension ImageFormat: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension ImageFormat: Encodable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

extension ImageFormat: Decodable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }
}

/// Sort direction for ``StorageFileAPI/list(path:options:)`` results.
///
/// Follows the `FunctionRegion` pattern: open to custom backend values.
public struct SortOrder: RawRepresentable, Hashable, Sendable {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let ascending = SortOrder(rawValue: "asc")
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

extension SortOrder: Decodable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }
}

/// Controls browser download behaviour for public and signed URLs.
///
/// Pass to ``StorageFileAPI/getPublicURL(path:download:options:cacheNonce:)``,
/// ``StorageFileAPI/createSignedURL(path:expiresIn:download:transform:cacheNonce:)``, or
/// ``StorageFileAPI/createSignedURLs(paths:expiresIn:download:cacheNonce:)``.
///
/// ## Example
///
/// ```swift
/// // Trigger download using the file's original filename
/// let url = try bucket.getPublicURL(path: "report.pdf", download: .download)
///
/// // Trigger download with a custom filename
/// let url = try bucket.getPublicURL(path: "report.pdf", download: .downloadAs("annual-2024.pdf"))
/// ```
public enum DownloadBehavior: Sendable {
  /// Trigger a browser download prompt using the file's original name.
  ///
  /// Wire format: appends `?download=` (empty string value) to the URL.
  case download

  /// Trigger a browser download prompt using a custom filename.
  ///
  /// Wire format: appends `?download=<filename>` to the URL.
  case downloadAs(String)
}

/// Options for on-the-fly image transformation via the Supabase Storage image transformation API.
///
/// Use `TransformOptions` when calling
/// ``StorageFileAPI/download(path:options:query:cacheNonce:)`` or
/// ``StorageFileAPI/getPublicURL(path:download:options:cacheNonce:)`` to resize, reformat, or
/// adjust the quality of images before they are served to the client.
///
/// ## Example
///
/// ```swift
/// // Serve a 200×200 thumbnail, retaining aspect ratio, at 75% quality
/// let url = try storage.from("avatars").getPublicURL(
///   path: "user-123/avatar.png",
///   options: TransformOptions(width: 200, height: 200, resize: "contain", quality: 75)
/// )
/// ```
public struct TransformOptions: Encodable, Sendable {
  /// The target width of the transformed image in pixels.
  public var width: Int?

  /// The target height of the transformed image in pixels.
  public var height: Int?

  /// Controls how the image is resized to fit the target dimensions.
  ///
  /// Supported values:
  /// - `"cover"` — Resizes to fill the target dimensions while maintaining the aspect ratio.
  ///   Portions of the image that overflow the bounds are cropped. This is the default.
  /// - `"contain"` — Resizes so the entire image fits within the target dimensions while
  ///   maintaining the aspect ratio. May leave empty space around the image.
  /// - `"fill"` — Stretches the image to exactly fill the target dimensions, ignoring the
  ///   original aspect ratio.
  public var resize: String?

  /// The quality of the returned image, from `20` (lowest) to `100` (highest).
  ///
  /// Applies to lossy formats such as JPEG and WebP. Defaults to `80`.
  public var quality: Int?

  /// The output format for the transformed image (e.g. `"origin"`, `"webp"`).
  ///
  /// Passing `"origin"` preserves the original format of the file. Leave `nil` to let the
  /// server choose an appropriate format.
  public var format: String?

  public init(
    width: Int? = nil,
    height: Int? = nil,
    resize: String? = nil,
    quality: Int? = nil,
    format: String? = nil
  ) {
    self.width = width
    self.height = height
    self.resize = resize
    self.quality = quality
    self.format = format
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
