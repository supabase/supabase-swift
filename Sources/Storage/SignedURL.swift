import Foundation

public struct SignedURL: Decodable {
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
