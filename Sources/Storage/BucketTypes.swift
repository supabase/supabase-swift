import Foundation

/// Whether a bucket holds files or analytics (Iceberg) tables.
///
/// ## Topics
///
/// ### Predefined types
///
/// - ``standard``
/// - ``analytics``
public struct BucketType: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The value Storage sends and expects, e.g. `"STANDARD"`.
  public let rawValue: String

  /// Creates a ``BucketType`` from the value Storage sends.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Creates a ``BucketType`` from a string literal.
  public init(stringLiteral value: String) { self.init(rawValue: value) }

  /// Decodes the raw value from a single string.
  public init(from decoder: any Decoder) throws {
    self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
  }

  /// Encodes the raw value as a single string.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// A bucket of files. The default.
  public static let standard = BucketType(rawValue: "STANDARD")

  /// A bucket of Iceberg tables.
  public static let analytics = BucketType(rawValue: "ANALYTICS")
}

/// Whether a bucket keeps a new version of an object on each write, as ``Bucket`` reports it.
///
/// ## Topics
///
/// ### Predefined statuses
///
/// - ``disabled``
/// - ``enabled``
/// - ``suspended``
public struct BucketVersioningStatus: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The value Storage sends, e.g. `"ENABLED"`.
  public let rawValue: String

  /// Creates a ``BucketVersioningStatus`` from the value Storage sends.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Creates a ``BucketVersioningStatus`` from a string literal.
  public init(stringLiteral value: String) { self.init(rawValue: value) }

  /// Versioning was never turned on. Each write replaces the object.
  public static let disabled = BucketVersioningStatus(rawValue: "DISABLED")

  /// Each write keeps the previous object as a noncurrent version.
  public static let enabled = BucketVersioningStatus(rawValue: "ENABLED")

  /// Versioning was turned on, then paused. Existing versions stay, but new writes replace the
  /// current version.
  public static let suspended = BucketVersioningStatus(rawValue: "SUSPENDED")
}

/// The versioning status to create a bucket with, for
/// `createBucket(_:options:)`.
///
/// A new bucket cannot start suspended, so this type has no `suspended` member.
///
/// ## Topics
///
/// ### Predefined statuses
///
/// - ``disabled``
/// - ``enabled``
public struct BucketVersioningCreateStatus: RawRepresentable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The value Storage expects, e.g. `"ENABLED"`.
  public let rawValue: String

  /// Creates a ``BucketVersioningCreateStatus`` from the value Storage expects.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Creates a ``BucketVersioningCreateStatus`` from a string literal.
  public init(stringLiteral value: String) { self.init(rawValue: value) }

  /// Create the bucket without versioning. The server default.
  public static let disabled = BucketVersioningCreateStatus(rawValue: "DISABLED")

  /// Create the bucket with versioning turned on.
  public static let enabled = BucketVersioningCreateStatus(rawValue: "ENABLED")
}

/// The versioning status to move a bucket to, for
/// `updateBucket(_:options:)`.
///
/// A bucket cannot go back to disabled, so this type has no `disabled` member.
///
/// ## Topics
///
/// ### Predefined statuses
///
/// - ``enabled``
/// - ``suspended``
public struct BucketVersioningUpdateStatus: RawRepresentable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The value Storage expects, e.g. `"SUSPENDED"`.
  public let rawValue: String

  /// Creates a ``BucketVersioningUpdateStatus`` from the value Storage expects.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Creates a ``BucketVersioningUpdateStatus`` from a string literal.
  public init(stringLiteral value: String) { self.init(rawValue: value) }

  /// Turn versioning on, or back on after a suspension.
  public static let enabled = BucketVersioningUpdateStatus(rawValue: "ENABLED")

  /// Pause versioning. Only a bucket that had versioning turned on can be suspended.
  public static let suspended = BucketVersioningUpdateStatus(rawValue: "SUSPENDED")
}

/// Options for `listBuckets(options:)`: paging, sort and a name filter.
///
/// ```swift
/// let buckets = try await storage.listBuckets(
///   options: BucketListOptions(limit: 20, sortBy: .createdAt, order: .descending))
/// ```
///
/// ## Topics
///
/// ### Creating list options
///
/// - ``init(limit:offset:sortBy:order:search:)``
///
/// ### Options
///
/// - ``limit``
/// - ``offset``
/// - ``sortBy``
/// - ``order``
/// - ``search``
public struct BucketListOptions: Hashable, Sendable {
  /// Maximum number of buckets to return. `nil` returns all of them.
  public var limit: Int?

  /// Zero-based offset used for paginating results.
  public var offset: Int?

  /// The column to sort by.
  public var sortBy: BucketSortColumn?

  /// The sort direction.
  public var order: SortOrder?

  /// A substring filter applied to bucket names.
  public var search: String?

  /// Creates a ``BucketListOptions`` value. A `nil` field is left to the server.
  ///
  /// - Parameters:
  ///   - limit: Maximum number of buckets to return.
  ///   - offset: Zero-based offset for pagination.
  ///   - sortBy: The column to sort by.
  ///   - order: The sort direction.
  ///   - search: A substring filter applied to bucket names.
  public init(
    limit: Int? = nil,
    offset: Int? = nil,
    sortBy: BucketSortColumn? = nil,
    order: SortOrder? = nil,
    search: String? = nil
  ) {
    self.limit = limit
    self.offset = offset
    self.sortBy = sortBy
    self.order = order
    self.search = search
  }

  /// The query items `GET /bucket` and `GET /iceberg/bucket` read.
  var queryItems: [URLQueryItem] {
    [
      limit.map { URLQueryItem(name: "limit", value: "\($0)") },
      offset.map { URLQueryItem(name: "offset", value: "\($0)") },
      sortBy.map { URLQueryItem(name: "sortColumn", value: $0.rawValue) },
      order.map { URLQueryItem(name: "sortOrder", value: $0.rawValue) },
      search.map { URLQueryItem(name: "search", value: $0) },
    ].compactMap { $0 }
  }
}

/// The column a bucket listing is sorted by.
///
/// ## Topics
///
/// ### Predefined columns
///
/// - ``id``
/// - ``name``
/// - ``createdAt``
/// - ``updatedAt``
public struct BucketSortColumn: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  /// The column name sent to Storage, e.g. `"created_at"`.
  public let rawValue: String

  /// Creates a ``BucketSortColumn`` from the column name Storage expects.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Creates a ``BucketSortColumn`` from a string literal.
  public init(stringLiteral value: String) { self.init(rawValue: value) }

  /// Sort by bucket ID.
  public static let id = BucketSortColumn(rawValue: "id")

  /// Sort by bucket name.
  public static let name = BucketSortColumn(rawValue: "name")

  /// Sort by the time the bucket was created.
  public static let createdAt = BucketSortColumn(rawValue: "created_at")

  /// Sort by the time the bucket was last updated.
  public static let updatedAt = BucketSortColumn(rawValue: "updated_at")
}

/// The settings of a new Storage bucket, for `createBucket(_:options:)`.
///
/// A `nil` field takes the server default: a private standard bucket with no size limit, every
/// MIME type and versioning off.
///
/// ```swift
/// try await storage.createBucket(
///   "user-uploads",
///   options: CreateBucketOptions(
///     isPublic: false,
///     fileSizeLimit: .megabytes(10),
///     allowedMimeTypes: ["image/png", "image/jpeg"],
///     versioningStatus: .enabled
///   )
/// )
/// ```
///
/// ## Topics
///
/// ### Creating bucket options
///
/// - ``init(isPublic:fileSizeLimit:allowedMimeTypes:type:versioningStatus:)``
///
/// ### Bucket settings
///
/// - ``isPublic``
/// - ``fileSizeLimit``
/// - ``allowedMimeTypes``
/// - ``type``
/// - ``versioningStatus``
public struct CreateBucketOptions: Hashable, Sendable {
  /// Whether the bucket is publicly accessible without an authorization token.
  public var isPublic: Bool?

  /// Maximum file size allowed for uploads.
  public var fileSizeLimit: ByteCount?

  /// MIME types accepted during upload, e.g. `["image/png", "image/*"]`.
  public var allowedMimeTypes: [String]?

  /// The bucket type. A bucket cannot change type later. Defaults to ``BucketType/standard``.
  public var type: BucketType?

  /// Whether the bucket keeps a new version of an object on each write. Defaults to
  /// ``BucketVersioningCreateStatus/disabled``.
  public var versioningStatus: BucketVersioningCreateStatus?

  /// Creates a ``CreateBucketOptions`` value. A `nil` field takes the server default.
  ///
  /// - Parameters:
  ///   - isPublic: Whether the bucket is publicly readable.
  ///   - fileSizeLimit: Maximum upload size, e.g. `.megabytes(10)`.
  ///   - allowedMimeTypes: Permitted MIME types.
  ///   - type: The bucket type.
  ///   - versioningStatus: Whether the bucket keeps a new version of an object on each write.
  public init(
    isPublic: Bool? = nil,
    fileSizeLimit: ByteCount? = nil,
    allowedMimeTypes: [String]? = nil,
    type: BucketType? = nil,
    versioningStatus: BucketVersioningCreateStatus? = nil
  ) {
    self.isPublic = isPublic
    self.fileSizeLimit = fileSizeLimit
    self.allowedMimeTypes = allowedMimeTypes
    self.type = type
    self.versioningStatus = versioningStatus
  }
}

/// The settings to change on an existing Storage bucket, for
/// `updateBucket(_:options:)`.
///
/// Only the fields that are set are sent, so the others keep their current value. A bucket cannot
/// change type, so this type has no `type` field.
///
/// ```swift
/// // Change one setting, keep the rest
/// try await storage.updateBucket("user-uploads", options: UpdateBucketOptions(isPublic: true))
/// try await storage.updateBucket(
///   "user-uploads", options: UpdateBucketOptions(versioningStatus: .suspended))
/// ```
///
/// ## Topics
///
/// ### Creating bucket options
///
/// - ``init(isPublic:fileSizeLimit:allowedMimeTypes:versioningStatus:)``
///
/// ### Bucket settings
///
/// - ``isPublic``
/// - ``fileSizeLimit``
/// - ``allowedMimeTypes``
/// - ``versioningStatus``
public struct UpdateBucketOptions: Hashable, Sendable {
  /// Whether the bucket is publicly accessible without an authorization token.
  public var isPublic: Bool?

  /// Maximum file size allowed for uploads.
  public var fileSizeLimit: ByteCount?

  /// MIME types accepted during upload, e.g. `["image/png", "image/*"]`.
  public var allowedMimeTypes: [String]?

  /// The versioning status to move the bucket to. A bucket must have had versioning turned on
  /// before it can be suspended.
  public var versioningStatus: BucketVersioningUpdateStatus?

  /// Creates an ``UpdateBucketOptions`` value. A `nil` field keeps its current value.
  ///
  /// - Parameters:
  ///   - isPublic: Whether the bucket is publicly readable.
  ///   - fileSizeLimit: Maximum upload size, e.g. `.megabytes(10)`.
  ///   - allowedMimeTypes: Permitted MIME types.
  ///   - versioningStatus: The versioning status to move the bucket to.
  public init(
    isPublic: Bool? = nil,
    fileSizeLimit: ByteCount? = nil,
    allowedMimeTypes: [String]? = nil,
    versioningStatus: BucketVersioningUpdateStatus? = nil
  ) {
    self.isPublic = isPublic
    self.fileSizeLimit = fileSizeLimit
    self.allowedMimeTypes = allowedMimeTypes
    self.versioningStatus = versioningStatus
  }
}
