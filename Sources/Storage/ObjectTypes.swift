public import Foundation

/// Options for `list(path:options:)`: paging, sort, a name filter and the
/// version filters.
///
/// ```swift
/// let options = ListOptions(limit: 50, sortBy: .createdAt, order: .descending, search: "avatar")
/// let files = try await storage.from("avatars").list(options: options)
/// ```
///
/// A `nil` field takes the server default: the first 100 entries, sorted by name ascending.
///
/// ## Topics
///
/// ### Creating list options
///
/// - ``init(limit:offset:sortBy:order:search:exactMatch:versions:deleteMarkers:)``
///
/// ### Paging and sorting
///
/// - ``limit``
/// - ``offset``
/// - ``sortBy``
/// - ``order``
///
/// ### Filtering
///
/// - ``search``
/// - ``exactMatch``
/// - ``versions``
/// - ``deleteMarkers``
public struct ListOptions: Sendable {
  /// Maximum number of entries to return. Defaults to `100`.
  public var limit: Int?

  /// Zero-based offset used for paginating results. Defaults to `0`.
  public var offset: Int?

  /// The column to sort by. Defaults to ``ObjectSortColumn/name``.
  public var sortBy: ObjectSortColumn?

  /// The sort direction. Defaults to ``SortOrder/ascending``.
  public var order: SortOrder?

  /// A substring filter applied to names within the listed folder.
  public var search: String?

  /// Whether `path` names one object rather than a folder. When `true`, Storage does not append
  /// a `/` to it.
  public var exactMatch: Bool?

  /// Whether noncurrent versions of versioned objects are left out, included, or the only
  /// entries returned.
  public var versions: VersionFilter?

  /// Whether delete markers are left out, included, or the only entries returned.
  public var deleteMarkers: VersionFilter?

  /// Creates a ``ListOptions`` value.
  ///
  /// - Parameters:
  ///   - limit: Maximum number of entries to return.
  ///   - offset: Zero-based offset for pagination.
  ///   - sortBy: The column to sort by.
  ///   - order: The sort direction.
  ///   - search: A substring filter applied to names.
  ///   - exactMatch: Whether `path` names one object rather than a folder.
  ///   - versions: The filter for noncurrent versions.
  ///   - deleteMarkers: The filter for delete markers.
  public init(
    limit: Int? = nil,
    offset: Int? = nil,
    sortBy: ObjectSortColumn? = nil,
    order: SortOrder? = nil,
    search: String? = nil,
    exactMatch: Bool? = nil,
    versions: VersionFilter? = nil,
    deleteMarkers: VersionFilter? = nil
  ) {
    self.limit = limit
    self.offset = offset
    self.sortBy = sortBy
    self.order = order
    self.search = search
    self.exactMatch = exactMatch
    self.versions = versions
    self.deleteMarkers = deleteMarkers
  }
}

/// The column a listing is sorted by.
///
/// ## Topics
///
/// ### Predefined columns
///
/// - ``name``
/// - ``updatedAt``
/// - ``createdAt``
/// - ``lastAccessedAt``
public struct ObjectSortColumn: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  /// The column name sent to Storage, e.g. `"updated_at"`.
  public let rawValue: String

  /// Creates an ``ObjectSortColumn`` from the column name Storage expects.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Creates a ``ObjectSortColumn`` from a string literal.
  public init(stringLiteral value: String) { self.init(rawValue: value) }

  /// Sort by object name.
  public static let name = ObjectSortColumn(rawValue: "name")

  /// Sort by the time the object was last updated.
  public static let updatedAt = ObjectSortColumn(rawValue: "updated_at")

  /// Sort by the time the object was created.
  public static let createdAt = ObjectSortColumn(rawValue: "created_at")

  /// Sort by the time the object was last read. Only `list(path:options:)`
  /// accepts it.
  public static let lastAccessedAt = ObjectSortColumn(rawValue: "last_accessed_at")
}

/// Whether a listing leaves out, includes, or returns only one kind of version entry.
///
/// Used for noncurrent versions and for delete markers in a versioned bucket. Storage rejects
/// either filter with ``StorageError/Code/featureNotEnabled`` when the project has no object
/// versioning.
///
/// ## Topics
///
/// ### Predefined filters
///
/// - ``exclude``
/// - ``include``
/// - ``only``
public struct VersionFilter: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  /// The value sent to Storage, e.g. `"include"`.
  public let rawValue: String

  /// Creates a ``VersionFilter`` from the value Storage expects.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Creates a ``VersionFilter`` from a string literal.
  public init(stringLiteral value: String) { self.init(rawValue: value) }

  /// Leave these entries out. The server default.
  public static let exclude = VersionFilter(rawValue: "exclude")

  /// Return these entries alongside the others.
  public static let include = VersionFilter(rawValue: "include")

  /// Return only these entries.
  public static let only = VersionFilter(rawValue: "only")
}

/// Options for ``StorageFileApi/copy(from:to:toBucket:sourceVersionID:options:)``.
///
/// ```swift
/// let copy = try await bucket.copy(
///   from: "a.png", to: "b.png",
///   options: CopyOptions(upsert: true, cacheControl: .noCache))
/// ```
///
/// ## Topics
///
/// ### Creating copy options
///
/// - ``init(upsert:copyMetadata:metadata:contentType:cacheControl:)``
///
/// ### Options
///
/// - ``upsert``
/// - ``copyMetadata``
/// - ``metadata``
/// - ``contentType``
/// - ``cacheControl``
public struct CopyOptions: Sendable {
  /// Whether the copy replaces an object already at the destination. Defaults to `false`, which
  /// makes the copy fail when the destination exists.
  public var upsert: Bool

  /// Whether the copy keeps the source's metadata. Defaults to `true`.
  public var copyMetadata: Bool

  /// User metadata for the copy, in place of the source's.
  public var metadata: JSONObject?

  /// The MIME type of the copy, in place of the source's.
  public var contentType: String?

  /// The `Cache-Control` of the copy, in place of the source's.
  public var cacheControl: CacheControl?

  /// Creates a ``CopyOptions`` value.
  ///
  /// - Parameters:
  ///   - upsert: Whether the copy replaces an object at the destination.
  ///   - copyMetadata: Whether the copy keeps the source's metadata.
  ///   - metadata: User metadata for the copy.
  ///   - contentType: The MIME type of the copy.
  ///   - cacheControl: The `Cache-Control` of the copy.
  public init(
    upsert: Bool = false,
    copyMetadata: Bool = true,
    metadata: JSONObject? = nil,
    contentType: String? = nil,
    cacheControl: CacheControl? = nil
  ) {
    self.upsert = upsert
    self.copyMetadata = copyMetadata
    self.metadata = metadata
    self.contentType = contentType
    self.cacheControl = cacheControl
  }
}

/// One entry of a bucket listing: a file, or a folder when listing one level at a time.
///
/// ``StorageObject`` is returned by `list(path:options:)` when it takes ``ListOptions``.
///
/// ## Topics
///
/// ### Identifying the object
///
/// - ``name``
/// - ``id``
/// - ``versionID``
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
  /// The name of the file, including its extension, relative to the listed prefix.
  public var name: String

  /// The unique identifier of this object. `nil` for a folder row.
  public var id: UUID?

  /// The version identifier of this object. `nil` for a folder row and on older servers.
  public var versionID: String?

  /// The date and time the object was created.
  public var createdAt: Date?

  /// The date and time the object was last updated.
  public var updatedAt: Date?

  /// The date and time the object was last accessed.
  public var lastAccessedAt: Date?

  /// What Storage recorded about the stored bytes: size, MIME type, ETag. `nil` for a folder row.
  public var metadata: ObjectMetadata?

  /// The metadata the uploader attached through ``UploadOptions/metadata``.
  public var userMetadata: JSONObject?

  /// Whether this object was created while the bucket had versioning enabled.
  public var isVersioned: Bool?

  /// Whether this entry is a delete marker rather than an object version.
  public var isDeleteMarker: Bool?

  /// The date and time this version was archived.
  public var archivedAt: Date?

  /// Whether this entry is a folder: `list(path:options:)` lists one level, and
  /// a folder arrives as a row with no ``id``.
  public var isFolder: Bool { id == nil }

  /// Creates a ``StorageObject``.
  public init(
    name: String,
    id: UUID? = nil,
    versionID: String? = nil,
    createdAt: Date? = nil,
    updatedAt: Date? = nil,
    lastAccessedAt: Date? = nil,
    metadata: ObjectMetadata? = nil,
    userMetadata: JSONObject? = nil,
    isVersioned: Bool? = nil,
    isDeleteMarker: Bool? = nil,
    archivedAt: Date? = nil
  ) {
    self.name = name
    self.id = id
    self.versionID = versionID
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
    case versionID = "version"
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
  public var cacheControl: CacheControl?

  /// When the bytes were last written.
  public var lastModified: Date?

  /// The `Content-Length` recorded at upload, usually equal to ``size``.
  public var contentLength: Int64?

  /// Every other key Storage sent, by its wire name.
  public var additional: JSONObject

  /// Creates an ``ObjectMetadata``.
  public init(
    eTag: String? = nil,
    size: Int64? = nil,
    mimeType: String? = nil,
    cacheControl: CacheControl? = nil,
    lastModified: Date? = nil,
    contentLength: Int64? = nil,
    additional: JSONObject = [:]
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

  /// Decodes the known keys and keeps every other key in ``additional``.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    eTag = try container.decodeIfPresent(String.self, forKey: .eTag)
    size = try container.decodeIfPresent(Int64.self, forKey: .size)
    mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
    cacheControl = try container.decodeIfPresent(CacheControl.self, forKey: .cacheControl)
    lastModified = try container.decodeIfPresent(String.self, forKey: .lastModified)?.date
    contentLength = try container.decodeIfPresent(Int64.self, forKey: .contentLength)

    let known = Set(CodingKeys.allCases.map(\.rawValue))
    let all = try decoder.singleValueContainer().decode(JSONObject.self)
    additional = all.filter { !known.contains($0.key) }
  }
}

/// Everything Storage knows about one object, returned by ``StorageFileApi/info(path:versionID:)``.
///
/// ## Topics
///
/// ### Identifying the object
///
/// - ``id``
/// - ``versionID``
/// - ``name``
/// - ``bucketID``
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
  public var versionID: String

  /// The full key of the object within its bucket.
  public var name: String

  /// The identifier of the bucket that contains this object.
  public var bucketID: String?

  /// The size in bytes.
  public var size: Int64?

  /// The MIME type, as sent in `Content-Type` at upload.
  public var contentType: String?

  /// The `Cache-Control` header stored with the object.
  public var cacheControl: CacheControl?

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
  public var userMetadata: JSONObject?

  /// Whether this object was created while the bucket had versioning enabled.
  public var isVersioned: Bool?

  /// Whether this entry is a delete marker rather than an object version.
  public var isDeleteMarker: Bool?

  /// The date and time this version was archived.
  public var archivedAt: Date?

  /// Creates an ``ObjectInfo``.
  public init(
    id: UUID,
    versionID: String,
    name: String,
    bucketID: String? = nil,
    size: Int64? = nil,
    contentType: String? = nil,
    cacheControl: CacheControl? = nil,
    eTag: String? = nil,
    lastModified: Date? = nil,
    createdAt: Date? = nil,
    updatedAt: Date? = nil,
    lastAccessedAt: Date? = nil,
    userMetadata: JSONObject? = nil,
    isVersioned: Bool? = nil,
    isDeleteMarker: Bool? = nil,
    archivedAt: Date? = nil
  ) {
    self.id = id
    self.versionID = versionID
    self.name = name
    self.bucketID = bucketID
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
    case versionID = "version"
    case name
    case bucketID = "bucket_id"
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
