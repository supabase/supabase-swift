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
    let existingResumeData = self.resumeData
    let dataToUse = resumeData ?? existingResumeData
    
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

/// Manages resume data for resumable upload tasks.
package class ResumeDataManager: @unchecked Sendable {
  package static let shared = ResumeDataManager()
  
  private let userDefaults: UserDefaults
  private let keyPrefix = "SupabaseResumableUpload_"
  private let maxAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
  private let lock = NSLock()
  
  private init() {
    self.userDefaults = UserDefaults(suiteName: "com.supabase.storage.resumable") ?? .standard
    cleanupExpiredData()
  }
  
  /// Stores resume data for a given task identifier.
  /// - Parameters:
  ///   - data: The resume data to store.
  ///   - identifier: The unique task identifier.
  package func storeResumeData(_ data: Data, for identifier: String) {
    lock.lock()
    defer { lock.unlock() }
    
    let metadata = ResumeDataMetadata(data: data, timestamp: Date())
    
    if let encoded = try? JSONEncoder().encode(metadata) {
      userDefaults.set(encoded, forKey: keyPrefix + identifier)
    }
  }
  
  /// Retrieves resume data for a given task identifier.
  /// - Parameter identifier: The unique task identifier.
  /// - Returns: The stored resume data, or nil if not found or expired.
  package func retrieveResumeData(for identifier: String) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    
    guard let encoded = userDefaults.data(forKey: keyPrefix + identifier),
          let metadata = try? JSONDecoder().decode(ResumeDataMetadata.self, from: encoded) else {
      return nil
    }
    
    // Check if data has expired
    if Date().timeIntervalSince(metadata.timestamp) > maxAge {
      clearResumeData(for: identifier)
      return nil
    }
    
    return metadata.data
  }
  
  /// Clears resume data for a given task identifier.
  /// - Parameter identifier: The unique task identifier.
  package func clearResumeData(for identifier: String) {
    lock.lock()
    defer { lock.unlock() }
    userDefaults.removeObject(forKey: keyPrefix + identifier)
  }
  
  /// Clears all stored resume data.
  package func clearAllResumeData() {
    lock.lock()
    defer { lock.unlock() }
    
    let keys = userDefaults.dictionaryRepresentation().keys
    for key in keys where key.hasPrefix(keyPrefix) {
      userDefaults.removeObject(forKey: key)
    }
  }
  
  /// Returns all stored resume data identifiers.
  package func getAllIdentifiers() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    
    return userDefaults.dictionaryRepresentation().keys
      .compactMap { key in
        if key.hasPrefix(keyPrefix) {
          return String(key.dropFirst(keyPrefix.count))
        }
        return nil
      }
  }
  
  /// Cleans up expired resume data entries.
  private func cleanupExpiredData() {
    let now = Date()
    let identifiers = getAllIdentifiers()
    
    for identifier in identifiers {
      lock.lock()
      let encoded = userDefaults.data(forKey: keyPrefix + identifier)
      lock.unlock()
      
      guard let encoded = encoded,
            let metadata = try? JSONDecoder().decode(ResumeDataMetadata.self, from: encoded) else {
        clearResumeData(for: identifier)
        continue
      }
      
      if now.timeIntervalSince(metadata.timestamp) > maxAge {
        clearResumeData(for: identifier)
      }
    }
  }
}

/// Metadata for stored resume data.
private struct ResumeDataMetadata: Codable {
  let data: Data
  let timestamp: Date
}

// Forward declaration - will be implemented in Phase 2
public enum StorageError: Error {
  case resumeDataUnavailable
  case streamingNotEnabled
  case backgroundUploadsNotEnabled
  case resumableUploadsNotEnabled
}