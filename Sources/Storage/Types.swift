import Foundation
import Helpers

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
  public var order: String?

  public init(column: String? = nil, order: String? = nil) {
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

  /// When upsert is set to true, the file is overwritten if it exists. When set to false, an error
  /// is thrown if the object already exists. Defaults to false.
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
  public let bucketId: String
  public let updatedAt: Date
  public let createdAt: Date
  public let lastAccessedAt: Date
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
