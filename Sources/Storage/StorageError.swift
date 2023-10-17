import Foundation

public struct StorageError: Error {
  public var statusCode: Int?
  public var message: String?

  public init(statusCode: Int? = nil, message: String? = nil) {
    self.statusCode = statusCode
    self.message = message
  }
}

extension StorageError: LocalizedError {
  public var errorDescription: String? {
    return message
  }
}
