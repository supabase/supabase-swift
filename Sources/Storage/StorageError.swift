import Foundation

public struct StorageError: Error, Decodable {
  public var statusCode: Int
  public var message: String
  public var error: String

  public init(statusCode: Int, message: String, error: String) {
    self.statusCode = statusCode
    self.message = message
    self.error = error
  }
}

extension StorageError: LocalizedError {
  public var errorDescription: String? {
    return message
  }
}
