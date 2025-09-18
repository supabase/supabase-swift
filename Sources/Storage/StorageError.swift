import Foundation

public struct StorageError: Error, Decodable, Sendable {
  public var statusCode: String?
  public var message: String
  public var error: String?

  public init(statusCode: String? = nil, message: String, error: String? = nil) {
    self.statusCode = statusCode
    self.message = message
    self.error = error
  }
}

extension StorageError: LocalizedError {
  public var errorDescription: String? {
    message
  }
}
