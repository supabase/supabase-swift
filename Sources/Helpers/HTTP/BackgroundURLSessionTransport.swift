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
  
  package init(identifier: String) {
    self.identifier = identifier
    let config = URLSessionConfiguration.background(withIdentifier: identifier)
    config.isDiscretionary = false
    config.allowsCellularAccess = true
    if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
      config.sessionSendsLaunchEvents = true
    }
    
    self.delegate = BackgroundSessionDelegate.shared
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
    
    // Create progress object
    let progress = Progress()
    progress.totalUnitCount = uploadTask.progress.totalUnitCount
    progress.addChild(uploadTask.progress, withPendingUnitCount: uploadTask.progress.totalUnitCount)
    
    // Store task metadata for lifecycle management
    let metadata = BackgroundTaskMetadata(
      identifier: taskIdentifier,
      taskIdentifier: uploadTask.taskIdentifier,
      startTime: Date(),
      fileURL: fileURL,
      request: urlRequest
    )
    
    BackgroundUploadManager.shared.registerTask(
      uploadTask,
      metadata: metadata
    )
    
    // Start the task
    uploadTask.resume()
    
    return BackgroundUploadTask(
      identifier: taskIdentifier,
      uploadTask: uploadTask,
      progress: progress,
      state: .running
    )
  }
}

/// Manages background upload tasks across app lifecycle.
package class BackgroundUploadManager: @unchecked Sendable {
  package static let shared = BackgroundUploadManager()
  
  private let userDefaults: UserDefaults
  private let taskMetadata = NSLock()
  private var _taskMetadata: [String: BackgroundTaskMetadata] = [:]
  
  private init() {
    self.userDefaults = UserDefaults(suiteName: "com.supabase.storage.background") ?? .standard
    restorePendingTasks()
  }
  
  package func registerTask(
    _ task: URLSessionUploadTask,
    metadata: BackgroundTaskMetadata
  ) {
    taskMetadata.lock()
    defer { taskMetadata.unlock() }
    
    _taskMetadata[metadata.identifier] = metadata
    
    // Persist to UserDefaults for app lifecycle survival
    if let data = try? JSONEncoder().encode(metadata) {
      userDefaults.set(data, forKey: "task_\(metadata.identifier)")
    }
  }
  
  package func removeTask(_ identifier: String) {
    taskMetadata.lock()
    defer { taskMetadata.unlock() }
    
    _taskMetadata.removeValue(forKey: identifier)
    userDefaults.removeObject(forKey: "task_\(identifier)")
  }
  
  private func restorePendingTasks() {
    let keys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("task_") }
    
    taskMetadata.lock()
    defer { taskMetadata.unlock() }
    
    for key in keys {
      guard let data = userDefaults.data(forKey: key),
            let metadata = try? JSONDecoder().decode(BackgroundTaskMetadata.self, from: data) else {
        continue
      }
      
      _taskMetadata[metadata.identifier] = metadata
    }
  }
  
  package func handleBackgroundEvents(for identifier: String, completionHandler: @escaping () -> Void) {
    // Handle background URL session events
    completionHandler()
  }
}

/// URLSessionDelegate for background operations.
package class BackgroundSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
  package static let shared = BackgroundSessionDelegate()
  
  private override init() {
    super.init()
  }
  
  package func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    // Handle task completion
    // Notify BackgroundUploadManager
  }
  
  package func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    // Handle progress updates
  }
  
  package func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    // Background session completed all tasks
  }
}

/// Metadata for background tasks.
package struct BackgroundTaskMetadata: Codable, Sendable {
  let identifier: String
  let taskIdentifier: Int
  let startTime: Date
  let fileURL: URL
  let request: URLRequest
  var bytesUploaded: Int64 = 0
  var totalBytes: Int64 = 0
  
  private enum CodingKeys: String, CodingKey {
    case identifier
    case taskIdentifier  
    case startTime
    case fileURL
    case requestURL
    case requestMethod
    case requestHeaders
    case bytesUploaded
    case totalBytes
  }
  
  package init(
    identifier: String,
    taskIdentifier: Int,
    startTime: Date,
    fileURL: URL,
    request: URLRequest
  ) {
    self.identifier = identifier
    self.taskIdentifier = taskIdentifier
    self.startTime = startTime
    self.fileURL = fileURL
    self.request = request
  }
  
  package init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    
    identifier = try container.decode(String.self, forKey: .identifier)
    taskIdentifier = try container.decode(Int.self, forKey: .taskIdentifier)
    startTime = try container.decode(Date.self, forKey: .startTime)
    fileURL = try container.decode(URL.self, forKey: .fileURL)
    bytesUploaded = try container.decode(Int64.self, forKey: .bytesUploaded)
    totalBytes = try container.decode(Int64.self, forKey: .totalBytes)
    
    // Reconstruct URLRequest
    let url = try container.decode(URL.self, forKey: .requestURL)
    let method = try container.decode(String.self, forKey: .requestMethod)
    let headers = try container.decode([String: String].self, forKey: .requestHeaders)
    
    var reconstructedRequest = URLRequest(url: url)
    reconstructedRequest.httpMethod = method
    for (key, value) in headers {
      reconstructedRequest.setValue(value, forHTTPHeaderField: key)
    }
    
    self.request = reconstructedRequest
  }
  
  package func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    
    try container.encode(identifier, forKey: .identifier)
    try container.encode(taskIdentifier, forKey: .taskIdentifier)
    try container.encode(startTime, forKey: .startTime)
    try container.encode(fileURL, forKey: .fileURL)
    try container.encode(bytesUploaded, forKey: .bytesUploaded)
    try container.encode(totalBytes, forKey: .totalBytes)
    
    // Encode URLRequest components
    if let url = request.url {
      try container.encode(url, forKey: .requestURL)
    }
    try container.encode(request.httpMethod ?? "POST", forKey: .requestMethod)
    
    var headers: [String: String] = [:]
    request.allHTTPHeaderFields?.forEach { headers[$0.key] = $0.value }
    try container.encode(headers, forKey: .requestHeaders)
  }
}