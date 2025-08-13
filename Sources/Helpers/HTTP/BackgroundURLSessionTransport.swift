import Foundation
import HTTPTypes
import HTTPTypesFoundation
import OpenAPIRuntime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A URLSession-based transport that supports background operations.
package struct BackgroundURLSessionTransport: BackgroundClientTransport {
  private let session: URLSession
  private let delegate: BackgroundSessionDelegate
  private let identifier: String
  
  package init(identifier: String, handler: (any BackgroundUploadHandler)? = nil) {
    self.identifier = identifier
    let config = URLSessionConfiguration.background(withIdentifier: identifier)
    config.isDiscretionary = false
    config.allowsCellularAccess = true
    if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
      config.sessionSendsLaunchEvents = true
    }
    
    self.delegate = BackgroundSessionDelegate.shared
    if let handler = handler {
      self.delegate.setHandler(handler)
    }
    self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
  }
  
  // MARK: - ClientTransport
  
  package func send(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    // Background transport doesn't support synchronous operations
    // Fall back to creating a background task and waiting for completion
    throw URLError(.unsupportedURL)
  }
  
  // MARK: - BackgroundClientTransport
  
  package func sendInBackground(
    _ request: HTTPTypes.HTTPRequest,
    fileURL: URL,
    baseURL: URL,
    operationID: String,
    taskIdentifier: String
  ) async throws -> BackgroundUploadTask {
    guard var urlRequest = URLRequest(httpRequest: request) else {
      throw URLError(.badURL)
    }
    
    // Resolve relative URLs against baseURL
    if let url = urlRequest.url, url.scheme == nil {
      urlRequest.url = URL(string: url.path, relativeTo: baseURL)
    }
    
    // Create upload task
    let uploadTask = session.uploadTask(with: urlRequest, fromFile: fileURL)
    uploadTask.taskDescription = taskIdentifier
    
    // Create progress object
    let progress = Progress()
    progress.totalUnitCount = 100
    
    // Create background upload task
    let backgroundTask = BackgroundUploadTask(
      identifier: taskIdentifier,
      path: "",
      fileURL: fileURL,
      uploadTask: uploadTask,
      progress: progress,
      state: .pending
    )
    
    // Register task with delegate
    delegate.registerTask(identifier: taskIdentifier, task: backgroundTask)
    
    // Start the task
    uploadTask.resume()
    
    return backgroundTask
  }
}

/// URLSessionDelegate for background operations.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
package class BackgroundSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
  package static let shared = BackgroundSessionDelegate()
  
  private var handler: (any BackgroundUploadHandler)?
  private var activeTasks: [String: BackgroundUploadTask] = [:]
  private let taskLock = NSLock()
  
  private override init() {
    super.init()
  }
  
  package func setHandler(_ handler: any BackgroundUploadHandler) {
    self.handler = handler
  }
  
  package func registerTask(identifier: String, task: BackgroundUploadTask) {
    taskLock.lock()
    activeTasks[identifier] = task
    taskLock.unlock()
  }
  
  package func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    guard let taskIdentifier = task.taskDescription else { return }
    
    Task {
      let response: Result<BackgroundUploadResponse, any Error>
      
      if let error = error {
        response = .failure(error)
      } else if let httpResponse = task.response as? HTTPURLResponse {
        let uploadResponse = BackgroundUploadResponse(
          identifier: taskIdentifier,
          path: "",
          statusCode: httpResponse.statusCode,
          responseData: nil
        )
        
        if (200..<300).contains(httpResponse.statusCode) {
          response = .success(uploadResponse)
        } else {
          let error = NSError(
            domain: "BackgroundUpload",
            code: httpResponse.statusCode,
            userInfo: [NSLocalizedDescriptionKey: "Upload failed with status code \(httpResponse.statusCode)"]
          )
          response = .failure(error)
        }
      } else {
        let error = NSError(
          domain: "BackgroundUpload",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Unknown error occurred"]
        )
        response = .failure(error)
      }
      
      // Notify handler
      await handler?.handleTaskCompletion(identifier: taskIdentifier, result: response)
      
      // Complete the task
      taskLock.lock()
      let backgroundTask = activeTasks.removeValue(forKey: taskIdentifier)
      taskLock.unlock()
      
      if let backgroundTask = backgroundTask {
        backgroundTask.complete(with: response)
      }
    }
  }
  
  package func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    guard let taskIdentifier = task.taskDescription else { return }
    
    Task {
      taskLock.lock()
      let backgroundTask = activeTasks[taskIdentifier]
      taskLock.unlock()
      
      if let backgroundTask = backgroundTask {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        backgroundTask.updateProgress(progress)
      }
    }
  }
  
  package func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    // Background session completed all tasks
  }
}