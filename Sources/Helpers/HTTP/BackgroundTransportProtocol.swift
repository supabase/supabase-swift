import Foundation
import HTTPTypes
import OpenAPIRuntime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A transport protocol that supports background operations.
package protocol BackgroundClientTransport: ClientTransport {
  /// Sends an HTTP request in the background that survives app lifecycle changes.
  /// - Parameters:
  ///   - request: The HTTP request to send.
  ///   - fileURL: The file URL for the upload data.
  ///   - baseURL: The base URL for the request.
  ///   - operationID: The operation identifier.
  ///   - taskIdentifier: A unique identifier for this background task.
  /// - Returns: A background upload task.
  func sendInBackground(
    _ request: HTTPTypes.HTTPRequest,
    fileURL: URL,
    baseURL: URL,
    operationID: String,
    taskIdentifier: String
  ) async throws -> BackgroundUploadTask
}

/// Represents a background upload task.
public struct BackgroundUploadTask: Sendable {
  public let identifier: String
  public let progress: Progress
  public let state: BackgroundTaskState
  private let uploadTask: URLSessionUploadTask
  
  package init(
    identifier: String,
    uploadTask: URLSessionUploadTask,
    progress: Progress,
    state: BackgroundTaskState
  ) {
    self.identifier = identifier
    self.uploadTask = uploadTask
    self.progress = progress
    self.state = state
  }
  
  public func cancel() async throws {
    uploadTask.cancel()
  }
  
  public func pause() async throws {
    uploadTask.suspend()
  }
  
  public func resume() async throws {
    uploadTask.resume()
  }
}

/// Represents the state of a background task.
public enum BackgroundTaskState: String, Codable, Sendable {
  case pending
  case running
  case paused
  case completed
  case failed
  case cancelled
}