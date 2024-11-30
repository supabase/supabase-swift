import Foundation

public struct BucketOptions: Sendable {
  /// The visibility of the bucket. Public buckets don't require an authorization token to download objects, but still require a valid token for all other operations. Bu default, buckets are private.
  public let `public`: Bool
  /// Specifies the allowed mime types that this bucket can accept during upload. The default value is null, which allows files with all mime types to be uploaded. Each mime type specified can be a wildcard, e.g. image/*, or a specific mime type, e.g. image/png.
  public let fileSizeLimit: String?
  /// Specifies the max file size in bytes that can be uploaded to this bucket. The global file size limit takes precedence over this value. The default value is null, which doesn't set a per bucket file size limit.
  public let allowedMimeTypes: [String]?

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
