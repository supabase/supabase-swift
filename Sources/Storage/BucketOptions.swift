import Foundation

public struct BucketOptions: Sendable {
  public let `public`: Bool
  public let fileSizeLimit: String?
  public let allowedMimeTypes: [String]?

  public init(public: Bool = false, fileSizeLimit: String? = nil, allowedMimeTypes: [String]? = nil) {
    self.public = `public`
    self.fileSizeLimit = fileSizeLimit
    self.allowedMimeTypes = allowedMimeTypes
  }
}
