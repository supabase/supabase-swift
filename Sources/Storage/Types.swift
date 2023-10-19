public struct SearchOptions: Encodable {
  public let prefix: String

  /// The number of files you want to be returned.
  public var limit: Int?

  /// The starting position.
  public var offset: Int?

  /// The column to sort by. Can be any column inside a ``FileObject``.
  public var sortBy: SortBy?

  /// The search string to filter files by.
  public var search: String?

  public init(
    prefix: String = "", limit: Int? = nil, offset: Int? = nil, sortBy: SortBy? = nil,
    search: String? = nil
  ) {
    self.prefix = prefix
    self.limit = limit
    self.offset = offset
    self.sortBy = sortBy
    self.search = search
  }
}

public struct SortBy: Encodable {
  public var column: String?
  public var order: String?

  public init(column: String? = nil, order: String? = nil) {
    self.column = column
    self.order = order
  }
}

public struct FileOptions {
  /// The number of seconds the asset is cached in the browser and in the Supabase CDN. This is set in the `Cache-Control: max-age=<seconds>` header. Defaults to 3600 seconds.
  public var cacheControl: String

  /// The `Content-Type` header value. Should be specified if using a `fileBody` that is neither `Blob` nor `File` nor `FormData`, otherwise will default to `text/plain;charset=UTF-8`.
  public var contentType: String

  /// When upsert is set to true, the file is overwritten if it exists. When set to false, an error is thrown if the object already exists. Defaults to false.
  public var upsert: Bool

  /// The duplex option is a string parameter that enables or disables duplex streaming, allowing for both reading and writing data in the same stream. It can be passed as an option to the fetch() method.
  public var duplex: String?

  public init(
    cacheControl: String = "3600",
    contentType: String = "text/plain;charset=UTF-8",
    upsert: Bool = false,
    duplex: String? = nil
  ) {
    self.cacheControl = cacheControl
    self.contentType = contentType
    self.upsert = upsert
    self.duplex = duplex
  }
}
