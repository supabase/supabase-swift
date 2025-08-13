import Foundation

/// Simple upload response for background tasks.
public struct BackgroundUploadResponse: Sendable {
  public let identifier: String
  public let path: String
  public let statusCode: Int
  public let responseData: Data?
  
  public init(identifier: String, path: String, statusCode: Int, responseData: Data? = nil) {
    self.identifier = identifier
    self.path = path
    self.statusCode = statusCode
    self.responseData = responseData
  }
}

/// Protocol for handling background upload completion.
public protocol BackgroundUploadHandler: AnyObject, Sendable {
  func handleTaskCompletion(identifier: String, result: Result<BackgroundUploadResponse, any Error>) async
}