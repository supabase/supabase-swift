import Foundation

public struct BucketOptions: Sendable {
  public let `public`: Bool
  public let fileSizeLimit: Int?
  public let allowedMimeTypes: [String]?

  public init(public: Bool = false, fileSizeLimit: Int? = nil, allowedMimeTypes: [String]? = nil) {
    self.public = `public`
    self.fileSizeLimit = fileSizeLimit
    self.allowedMimeTypes = allowedMimeTypes
  }
}
