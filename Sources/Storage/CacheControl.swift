import Foundation

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
public struct CacheControl: RawRepresentable, Decodable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The header value as sent, e.g. `"max-age=3600"`.
  public let rawValue: String

  /// Creates a ``CacheControl`` from a header value, sent as is.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``CacheControl`` from a string literal.
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
