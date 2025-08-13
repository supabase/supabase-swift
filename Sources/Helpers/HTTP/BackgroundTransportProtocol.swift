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
public class BackgroundUploadTask: @unchecked Sendable {
  public let identifier: String
  public let path: String
  public let fileURL: URL
  public let progress: Progress
  public private(set) var state: BackgroundTaskState
  private let uploadTask: URLSessionUploadTask
  
  // Completion handler for when the task completes
  public var completionHandler: (@Sendable (Result<BackgroundUploadResponse, any Error>) -> Void)?
  
  package init(
    identifier: String,
    path: String,
    fileURL: URL,
    uploadTask: URLSessionUploadTask,
    progress: Progress,
    state: BackgroundTaskState = .pending
  ) {
    self.identifier = identifier
    self.path = path
    self.fileURL = fileURL
    self.uploadTask = uploadTask
    self.progress = progress
    self.state = state
  }
  
  public func cancel() {
    uploadTask.cancel()
    state = .cancelled
  }
  
  public func pause() {
    uploadTask.suspend()
    state = .paused
  }
  
  public func resume() {
    uploadTask.resume()
    state = .running
  }
  
  /// Updates the progress of the upload task.
  /// - Parameter newProgress: The new progress value (0.0 to 1.0).
  public func updateProgress(_ newProgress: Double) {
    progress.completedUnitCount = Int64(newProgress * Double(progress.totalUnitCount))
    if state == .pending {
      state = .running
    }
  }
  
  /// Called when the background task completes.
  /// - Parameter result: The completion result.
  public func complete(with result: Result<BackgroundUploadResponse, any Error>) {
    switch result {
    case .success:
      state = .completed
      progress.completedUnitCount = progress.totalUnitCount
    case .failure:
      state = .failed
    }
    
    completionHandler?(result)
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