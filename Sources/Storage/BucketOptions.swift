import Foundation

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
