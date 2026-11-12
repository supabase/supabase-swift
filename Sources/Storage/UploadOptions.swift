import Foundation
public import HTTPTypes

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
  ///
  /// On this version an upload is a multipart form, which can only carry a `max-age=...` value
  /// or ``CacheControl/noCache``. Any other value, such as ``CacheControl/noStore``, makes the
  /// upload throw ``StorageError`` with kind ``StorageError/Kind-swift.struct/invalidRequest``
  /// before it sends anything.
  public var cacheControl: CacheControl

  /// When `true`, ``StorageFileApi/upload(path:data:options:)`` overwrites an existing file at
  /// the same path. When `false` (the default), it throws
  /// ``StorageError/Code-swift.struct/keyAlreadyExists``.
  ///
  /// ``StorageFileApi/update(path:data:options:)`` always overwrites and ignores this flag. For
  /// ``StorageFileApi/uploadToSignedURL(path:token:data:options:)`` Storage takes it from the
  /// token.
  public var upsert: Bool

  /// Arbitrary key-value metadata to attach to the uploaded object. You can later use this to
  /// filter or search for files.
  public var metadata: JSONObject?

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
    metadata: JSONObject? = nil,
    headers: HTTPFields = [:]
  ) {
    self.contentType = contentType
    self.cacheControl = cacheControl
    self.upsert = upsert
    self.metadata = metadata
    self.headers = headers
  }
}

/// What an upload request carries, whichever options type the caller used.
struct UploadParameters {
  /// The multipart `cacheControl` field. Storage stores `max-age=<field>`, and `no-cache` when
  /// the field is absent.
  var cacheControlField: String?
  var cacheControlHeader: String
  var contentType: String?
  var upsert: Bool
  var duplex: String?
  var metadata: JSONObject?
  var headers: HTTPFields
}

extension UploadParameters {
  init(_ options: UploadOptions) throws {
    guard let cacheControlField = options.cacheControl.multipartField else {
      throw StorageError(
        kind: .invalidRequest,
        message:
          "This version uploads a multipart form, which cannot carry the Cache-Control value '\(options.cacheControl.rawValue)'. Use a max-age value or no-cache."
      )
    }
    self.init(
      cacheControlField: cacheControlField.value,
      cacheControlHeader: options.cacheControl.rawValue,
      contentType: options.contentType,
      upsert: options.upsert,
      duplex: nil,
      metadata: options.metadata,
      headers: options.headers
    )
  }
}

extension CacheControl {
  struct MultipartField {
    /// The field value, or `nil` when the field must be left out.
    var value: String?
  }

  /// How a multipart upload says this value, or `nil` when it cannot: Storage rebuilds the
  /// header as `max-age=<field>`, and stores `no-cache` when the field is absent.
  var multipartField: MultipartField? {
    if self == .noCache {
      return MultipartField(value: nil)
    }
    let prefix = "max-age="
    guard rawValue.hasPrefix(prefix), rawValue.count > prefix.count else { return nil }
    return MultipartField(value: String(rawValue.dropFirst(prefix.count)))
  }
}
