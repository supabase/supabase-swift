import Foundation
import HTTPTypes
import OpenAPIRuntime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A transport protocol that supports resumable operations.
package protocol ResumableClientTransport: ClientTransport {
  /// Sends an HTTP request with resumable capability.
  /// - Parameters:
  ///   - request: The HTTP request to send.
  ///   - fileURL: The file URL for the upload data.
  ///   - baseURL: The base URL for the request.
  ///   - operationID: The operation identifier.
  ///   - resumeData: Optional resume data from a previous attempt.
  /// - Returns: A resumable upload task.
  func sendResumable(
    _ request: HTTPTypes.HTTPRequest,
    fileURL: URL,
    baseURL: URL,
    operationID: String,
    resumeData: Data?
  ) async throws -> ResumableUploadTask
}

/// Represents a resumable upload task.
public class ResumableUploadTask: @unchecked Sendable {
  public let identifier: String
  public let progress: Progress
  private var uploadTask: URLSessionUploadTask
  private let session: URLSession
  private let originalRequest: URLRequest
  private let fileURL: URL
  
  package init(
    identifier: String,
    uploadTask: URLSessionUploadTask,
    session: URLSession,
    originalRequest: URLRequest,
    fileURL: URL
  ) {
    self.identifier = identifier
    self.uploadTask = uploadTask
    self.session = session
    self.originalRequest = originalRequest
    self.fileURL = fileURL
    self.progress = Progress(totalUnitCount: 0)
    
    // Link URLSessionTask progress to our Progress
    if uploadTask.progress.totalUnitCount > 0 {
      progress.totalUnitCount = uploadTask.progress.totalUnitCount
      progress.addChild(uploadTask.progress, withPendingUnitCount: uploadTask.progress.totalUnitCount)
    }
  }
  
  public var resumeData: Data? {
    ResumeDataManager.shared.retrieveResumeData(for: identifier)
  }
  
  public func pause() async throws -> Data? {
    return try await withCheckedThrowingContinuation { continuation in
      if #available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *) {
        uploadTask.cancel { resumeData in
          if let resumeData = resumeData {
            ResumeDataManager.shared.storeResumeData(resumeData, for: self.identifier)
            continuation.resume(returning: resumeData)
          } else {
            continuation.resume(throwing: StorageError.resumeDataUnavailable)
          }
        }
      } else {
        // Fallback for older versions - just cancel without resume data
        uploadTask.cancel()
        continuation.resume(returning: nil)
      }
    }
  }
  
  public func resume(from resumeData: Data? = nil) async throws {
    let dataToUse = resumeData ?? self.resumeData
    
    if let resumeData = dataToUse {
      // Resume from existing data
      if #available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *) {
        self.uploadTask = session.uploadTask(withResumeData: resumeData)
      } else {
        // Fallback for older versions - restart from beginning
        self.uploadTask = session.uploadTask(with: originalRequest, fromFile: fileURL)
      }
    } else {
      // Restart from beginning
      self.uploadTask = session.uploadTask(with: originalRequest, fromFile: fileURL)
    }
    
    uploadTask.resume()
  }
  
  public func cancel() {
    uploadTask.cancel()
    ResumeDataManager.shared.clearResumeData(for: identifier)
  }
}

// Forward declaration - will be implemented in Phase 4
package class ResumeDataManager: @unchecked Sendable {
  package static let shared = ResumeDataManager()
  private init() {}
  
  package func storeResumeData(_ data: Data, for identifier: String) {
    // Implementation will be added in Phase 4
  }
  
  package func retrieveResumeData(for identifier: String) -> Data? {
    // Implementation will be added in Phase 4
    return nil
  }
  
  package func clearResumeData(for identifier: String) {
    // Implementation will be added in Phase 4
  }
}

// Forward declaration - will be implemented in Phase 2
public enum StorageError: Error {
  case resumeDataUnavailable
  case streamingNotEnabled
  case backgroundUploadsNotEnabled
  case resumableUploadsNotEnabled
}