import Foundation
import Helpers

/// Manages background upload tasks with persistence and error recovery.
public actor BackgroundUploadManager: BackgroundUploadHandler {
  
  private let userDefaultsKey = "SupabaseStorageBackgroundTasks"
  private var activeTasks: [String: BackgroundUploadTask] = [:]
  
  /// Singleton instance for shared task management.
  public static let shared = BackgroundUploadManager()
  
  private init() {
    // Load persisted tasks on initialization
    Task {
      await loadPersistedTasks()
    }
  }
  
  /// Registers a background upload task for management.
  /// - Parameter task: The background upload task to register.
  public func register(task: BackgroundUploadTask) {
    activeTasks[task.identifier] = task
    persistTaskMetadata(task)
  }
  
  /// Retrieves a background upload task by identifier.
  /// - Parameter identifier: The unique task identifier.
  /// - Returns: The background upload task if found, nil otherwise.
  public func task(for identifier: String) -> BackgroundUploadTask? {
    return activeTasks[identifier]
  }
  
  /// Removes a completed or canceled background upload task.
  /// - Parameter identifier: The unique task identifier.
  public func removeTask(identifier: String) {
    activeTasks.removeValue(forKey: identifier)
    removePersistedTask(identifier)
  }
  
  /// Returns all currently active background upload tasks.
  /// - Returns: Array of active background upload tasks.
  public var allTasks: [BackgroundUploadTask] {
    return Array(activeTasks.values)
  }
  
  /// Handles completion of a background upload task (BackgroundUploadHandler protocol).
  /// - Parameters:
  ///   - identifier: The task identifier.
  ///   - result: The upload result or error.
  public func handleTaskCompletion(identifier: String, result: Result<BackgroundUploadResponse, any Error>) {
    guard let task = activeTasks[identifier] else { return }
    
    // Update task with result
    task.complete(with: result)
    
    // Set a completion handler that converts the result type for storage callbacks
    task.completionHandler = { backgroundResult in
      _ = backgroundResult.map { bgResponse in
        FileUploadResponse(
          id: bgResponse.identifier,
          path: bgResponse.path,
          fullPath: bgResponse.path
        )
      }
      // Additional storage-specific completion logic can go here
    }
    
    // Remove from active tasks
    removeTask(identifier: identifier)
  }
  
  /// Pauses a background upload task.
  /// - Parameter identifier: The task identifier.
  public func pauseTask(identifier: String) async {
    guard let task = activeTasks[identifier] else { return }
    task.pause()
  }
  
  /// Resumes a paused background upload task.
  /// - Parameter identifier: The task identifier.
  public func resumeTask(identifier: String) async {
    guard let task = activeTasks[identifier] else { return }
    task.resume()
  }
  
  /// Cancels a background upload task.
  /// - Parameter identifier: The task identifier.
  public func cancelTask(identifier: String) async {
    guard let task = activeTasks[identifier] else { return }
    task.cancel()
    removeTask(identifier: identifier)
  }
  
  // MARK: - Private Methods
  
  private func persistTaskMetadata(_ task: BackgroundUploadTask) {
    let metadata: [String: Any] = [
      "identifier": task.identifier,
      "path": task.path,
      "fileURL": task.fileURL.path,
      "timestamp": Date().timeIntervalSince1970
    ]
    
    var allMetadata = UserDefaults.standard.dictionary(forKey: userDefaultsKey) ?? [:]
    allMetadata[task.identifier] = metadata
    UserDefaults.standard.set(allMetadata, forKey: userDefaultsKey)
  }
  
  private func removePersistedTask(_ identifier: String) {
    var allMetadata = UserDefaults.standard.dictionary(forKey: userDefaultsKey) ?? [:]
    allMetadata.removeValue(forKey: identifier)
    UserDefaults.standard.set(allMetadata, forKey: userDefaultsKey)
  }
  
  private func loadPersistedTasks() {
    // Note: In a real implementation, we would reconstruct BackgroundUploadTask
    // instances from persisted metadata. For this POC, we'll just clean up old entries.
    let now = Date().timeIntervalSince1970
    let maxAge: TimeInterval = 24 * 60 * 60 // 24 hours
    
    guard var allMetadata = UserDefaults.standard.dictionary(forKey: userDefaultsKey) else { return }
    
    // Remove tasks older than maxAge
    allMetadata = allMetadata.compactMapValues { value in
      guard let taskData = value as? [String: Any],
            let timestamp = taskData["timestamp"] as? TimeInterval else {
        return nil
      }
      
      return (now - timestamp) < maxAge ? value : nil
    }
    
    UserDefaults.standard.set(allMetadata, forKey: userDefaultsKey)
  }
}

// MARK: - Background Session Delegate

/// Delegate for handling background session events.
public class BackgroundSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
  
  /// Called when a background session completes all tasks.
  public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    // This is called when all background tasks for a session have completed.
    // We should notify the app that background processing is done.
    
    #if os(iOS)
    DispatchQueue.main.async {
      if let appDelegate = UIApplication.shared.delegate,
         let backgroundCompletionHandler = (appDelegate as? BackgroundSessionHandling)?.backgroundCompletionHandler {
        backgroundCompletionHandler()
      }
    }
    #endif
  }
  
  /// Called when a background task completes.
  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    guard let taskIdentifier = task.taskDescription else { return }
    
    Task {
      if let error = error {
        await BackgroundUploadManager.shared.handleTaskCompletion(
          identifier: taskIdentifier,
          result: .failure(error)
        )
      } else if let httpResponse = task.response as? HTTPURLResponse {
        // Handle successful response
        if (200..<300).contains(httpResponse.statusCode) {
          // In a real implementation, we'd need to get the response data
          // For now, we'll create a simple success response
          let response = BackgroundUploadResponse(
            identifier: taskIdentifier,
            path: "",
            statusCode: httpResponse.statusCode,
            responseData: nil
          )
          await BackgroundUploadManager.shared.handleTaskCompletion(
            identifier: taskIdentifier,
            result: .success(response)
          )
        } else {
          let error = NSError(
            domain: "BackgroundUpload",
            code: httpResponse.statusCode,
            userInfo: [NSLocalizedDescriptionKey: "Upload failed with status code \(httpResponse.statusCode)"]
          )
          await BackgroundUploadManager.shared.handleTaskCompletion(
            identifier: taskIdentifier,
            result: .failure(error)
          )
        }
      }
    }
  }
  
  /// Called when a task sends data.
  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    guard let taskIdentifier = task.taskDescription else { return }
    
    Task {
      if let backgroundTask = await BackgroundUploadManager.shared.task(for: taskIdentifier) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        backgroundTask.updateProgress(progress)
      }
    }
  }
}

// MARK: - Supporting Protocol

#if os(iOS)
/// Protocol for handling background session completion in app delegates.
public protocol BackgroundSessionHandling {
  var backgroundCompletionHandler: (() -> Void)? { get set }
}
#endif