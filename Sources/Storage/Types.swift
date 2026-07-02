import Foundation

public struct SearchOptions: Encodable, Sendable {
  var prefix: String

  /// The number of files you want to be returned.
  public var limit: Int?

  /// The starting position.
  public var offset: Int?

  /// The column to sort by. Can be any column inside a ``FileObject``.
  public var sortBy: SortBy?

  /// The search string to filter files by.
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

public struct SortBy: Encodable, Sendable {
  public var column: String?
  public var order: SortOrder?

  public init(column: String? = nil, order: SortOrder? = nil) {
    self.column = column
    self.order = order
  }
}

public struct FileOptions: Sendable {
  /// The number of seconds the asset is cached in the browser and in the Supabase CDN. This is set
  /// in the `Cache-Control: max-age=<seconds>` header. Defaults to 3600 seconds.
  public var cacheControl: String

  /// The `Content-Type` header value.
  public var contentType: String?

  /// When upsert is set to `true`, the file is overwritten if it exists. When set to `false`, an error
  /// is thrown if the object already exists. Defaults to `false`.
  public var upsert: Bool

  /// The duplex option is a string parameter that enables or disables duplex streaming, allowing
  /// for both reading and writing data in the same stream. It can be passed as an option to the
  /// fetch() method.
  public var duplex: String?

  /// The metadata option is an object that allows you to store additional information about the file.
  /// This information can be used to filter and search for files.
  /// The metadata object can contain any key-value pairs you want to store.
  public var metadata: [String: AnyJSON]?

  /// Optionally add extra headers.
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

public struct SignedURL: Decodable, Sendable {
  /// An optional error message.
  public var error: String?

  /// The signed url.
  public var signedURL: URL

  /// The path of the file.
  public var path: String

  public init(error: String? = nil, signedURL: URL, path: String) {
    self.error = error
    self.signedURL = signedURL
    self.path = path
  }
}

/// Represents the per-item result of a ``StorageFileApi/createSignedURLs(paths:expiresIn:download:)`` call.
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

public struct SignedUploadURL: Sendable {
  public let signedURL: URL
  public let path: String
  public let token: String
}

public struct FileUploadResponse: Sendable {
  public let id: String
  public let path: String
  public let fullPath: String
}

public struct SignedURLUploadResponse: Sendable {
  public let path: String
  public let fullPath: String
}

public struct CreateSignedUploadURLOptions: Sendable {
  public var upsert: Bool

  public init(upsert: Bool) {
    self.upsert = upsert
  }
}

public struct DestinationOptions: Sendable {
  public var destinationBucket: String?

  public init(destinationBucket: String? = nil) {
    self.destinationBucket = destinationBucket
  }
}

public struct FileObject: Identifiable, Hashable, Codable, Sendable {
  public var name: String
  public var bucketId: String?
  public var owner: String?
  public var id: UUID?
  public var updatedAt: Date?
  public var createdAt: Date?
  public var lastAccessedAt: Date?
  public var metadata: [String: AnyJSON]?
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

public struct FileObjectV2: Identifiable, Hashable, Decodable, Sendable {
  public let id: String
  public let version: String
  public let name: String
  public let bucketId: String?
  public let updatedAt: Date?
  public let createdAt: Date?
  public let lastAccessedAt: Date?
  public let size: Int?
  public let cacheControl: String?
  public let contentType: String?
  public let etag: String?
  public let lastModified: Date?
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

public struct Bucket: Identifiable, Hashable, Codable, Sendable {
  public var id: String
  public var name: String
  public var owner: String
  public var isPublic: Bool
  public var createdAt: Date
  public var updatedAt: Date
  public var allowedMimeTypes: [String]?
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

// MARK: - StorageByteCount

/// A strongly-typed file size value.
///
/// ```swift
/// BucketOptions(fileSizeLimit: .megabytes(5))
/// BucketOptions(fileSizeLimit: 10_485_760)  // raw bytes via integer literal
/// BucketOptions(fileSizeLimit: "1mb")        // human-readable string, passed verbatim to the server
/// ```
public struct StorageByteCount: Sendable, Hashable {
  /// The raw byte count, or `nil` when the value is a human-readable string such as `"1mb"`.
  public let bytes: Int64?

  // Stored verbatim and sent to the server when non-nil (e.g. "1mb", "500kb").
  let _stringValue: String?

  public init(_ bytes: Int64) {
    self.bytes = bytes
    self._stringValue = nil
  }

  public static func bytes(_ value: Int64) -> Self { Self(value) }
  public static func kilobytes(_ value: Int64) -> Self { Self(value * 1_024) }
  public static func megabytes(_ value: Int64) -> Self { Self(value * 1_024 * 1_024) }
  public static func gigabytes(_ value: Int64) -> Self { Self(value * 1_024 * 1_024 * 1_024) }
}

extension StorageByteCount: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int64) { self.init(value) }
}

extension StorageByteCount: ExpressibleByStringLiteral {
  /// Accepts a human-readable size string (e.g. `"1mb"`, `"500kb"`, `"2gb"`) or a plain
  /// numeric string (e.g. `"10485760"`). Plain numeric strings are converted to a byte count;
  /// all other strings are stored verbatim and forwarded to the server as-is.
  public init(stringLiteral value: String) {
    if let n = Int64(value) {
      bytes = n
      _stringValue = nil
    } else {
      bytes = nil
      _stringValue = value
    }
  }
}

extension StorageByteCount: Encodable {
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    if let string = _stringValue {
      try container.encode(string)
    } else {
      try container.encode(bytes ?? 0)
    }
  }
}

// MARK: - ResizeMode

/// Resize mode for on-the-fly image transformation.
///
/// Open-ended struct so custom backend values don't require an SDK update.
/// ```swift
/// TransformOptions(resize: .cover)
/// TransformOptions(resize: "cover")  // string literal still works
/// ```
public struct ResizeMode: RawRepresentable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let cover = ResizeMode(rawValue: "cover")
  public static let contain = ResizeMode(rawValue: "contain")
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

/// Output format for on-the-fly image transformation.
///
/// Open-ended struct so custom backend values don't require an SDK update.
/// ```swift
/// TransformOptions(format: .webp)
/// TransformOptions(format: "webp")  // string literal still works
/// ```
public struct ImageFormat: RawRepresentable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let origin = ImageFormat(rawValue: "origin")
  public static let webp = ImageFormat(rawValue: "webp")
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
/// Open-ended struct so custom backend values don't require an SDK update.
/// ```swift
/// SortBy(column: "name", order: .ascending)
/// SortBy(column: "name", order: "asc")  // string literal still works
/// ```
public struct SortOrder: RawRepresentable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let ascending = SortOrder(rawValue: "asc")
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

/// Controls the `?download=` query parameter on signed and public URLs.
///
/// ```swift
/// storage.from("docs").getPublicURL(path: "report.pdf", download: .withOriginalName)
/// storage.from("docs").getPublicURL(path: "report.pdf", download: .named("annual-2024.pdf"))
/// ```
public enum DownloadBehavior: Sendable {
  /// Trigger a browser download using the file's original name. Wire: `?download=`
  case withOriginalName
  /// Trigger a browser download with a custom filename. Wire: `?download=<name>`
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
public struct BucketOptions: Sendable {
  /// Whether the bucket is publicly accessible without an authorization token.
  public var isPublic: Bool

  /// The maximum file size allowed for uploads.
  ///
  /// Use ``StorageByteCount`` factory methods: `.megabytes(5)`, `.gigabytes(1)`,
  /// or an integer literal for raw bytes. `nil` means no per-bucket limit.
  public var fileSizeLimit: StorageByteCount?

  /// MIME types accepted during upload. Each entry can be exact (`"image/png"`) or
  /// a wildcard (`"image/*"`). `nil` allows all MIME types.
  public var allowedMimeTypes: [String]?

  public init(
    isPublic: Bool = false,
    fileSizeLimit: StorageByteCount? = nil,
    allowedMimeTypes: [String]? = nil
  ) {
    self.isPublic = isPublic
    self.fileSizeLimit = fileSizeLimit
    self.allowedMimeTypes = allowedMimeTypes
  }

  // MARK: Deprecated bridges

  @available(*, deprecated, renamed: "isPublic")
  public var `public`: Bool {
    get { isPublic }
    set { isPublic = newValue }
  }

  @_disfavoredOverload
  @available(*, deprecated, renamed: "init(isPublic:fileSizeLimit:allowedMimeTypes:)")
  public init(
    public isPublic: Bool = false,
    fileSizeLimit: String? = nil,
    allowedMimeTypes: [String]? = nil
  ) {
    self.init(
      isPublic: isPublic,
      fileSizeLimit: fileSizeLimit.map { StorageByteCount(stringLiteral: $0) },
      allowedMimeTypes: allowedMimeTypes
    )
  }
}

// MARK: - TransformOptions

/// Transform the asset before serving it to the client.
public struct TransformOptions: Encodable, Sendable {
  /// The width of the image in pixels.
  public var width: Int?
  /// The height of the image in pixels.
  public var height: Int?
  /// The resize mode can be cover, contain or fill. Defaults to cover.
  /// Cover resizes the image to maintain it's aspect ratio while filling the entire width and height.
  /// Contain resizes the image to maintain it's aspect ratio while fitting the entire image within the width and height.
  /// Fill resizes the image to fill the entire width and height. If the object's aspect ratio does not match the width and height, the image will be stretched to fit.
  public var resize: ResizeMode?
  /// Set the quality of the returned image. A number from 20 to 100, with 100 being the highest quality. Defaults to 80.
  public var quality: Int?
  /// Specify the format of the image requested.
  public var format: ImageFormat?

  public init(
    width: Int? = nil,
    height: Int? = nil,
    resize: ResizeMode? = nil,
    quality: Int? = nil,
    format: ImageFormat? = nil
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
      items.append(URLQueryItem(name: "resize", value: resize.rawValue))
    }

    if let quality {
      items.append(URLQueryItem(name: "quality", value: String(quality)))
    }

    if let format {
      items.append(URLQueryItem(name: "format", value: format.rawValue))
    }

    return items
  }
}
