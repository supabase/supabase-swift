import Foundation
import HTTPTypes
import HTTPTypesFoundation
import OpenAPIRuntime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A URLSession-based transport that supports resumable operations.
package struct ResumableURLSessionTransport: ResumableClientTransport {
  private let session: URLSession
  private let delegate: ResumableSessionDelegate
  
  package init(configuration: URLSessionConfiguration? = nil) {
    let config = configuration ?? {
      let c = URLSessionConfiguration.default
      c.allowsCellularAccess = true
      c.waitsForConnectivity = true
      c.timeoutIntervalForRequest = 60
      c.timeoutIntervalForResource = 0 // No timeout for long uploads
      return c
    }()
    
    self.delegate = ResumableSessionDelegate()
    self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
  }
  
  // MARK: - ClientTransport
  
  package func send(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    guard var urlRequest = URLRequest(httpRequest: request) else {
      throw URLError(.badURL)
    }
    
    // Resolve relative URLs against baseURL
    if let url = urlRequest.url, url.scheme == nil {
      urlRequest.url = URL(string: url.path, relativeTo: baseURL)
    }
    
    if let body = body {
      urlRequest.httpBody = try await Data(collecting: body, upTo: .max)
    }
    
    let (data, response) = try await session.data(for: urlRequest)
    
    guard let httpURLResponse = response as? HTTPURLResponse,
          let httpResponse = httpURLResponse.httpResponse else {
      throw URLError(.badServerResponse)
    }
    
    return (httpResponse, HTTPBody(data))
  }
  
  // MARK: - ResumableClientTransport
  
  package func sendResumable(
    _ request: HTTPTypes.HTTPRequest,
    fileURL: URL,
    baseURL: URL,
    operationID: String,
    resumeData: Data?
  ) async throws -> ResumableUploadTask {
    guard var urlRequest = URLRequest(httpRequest: request) else {
      throw URLError(.badURL)
    }
    
    // Resolve relative URLs against baseURL
    if let url = urlRequest.url, url.scheme == nil {
      urlRequest.url = URL(string: url.path, relativeTo: baseURL)
    }
    
    let taskIdentifier = UUID().uuidString
    
    // Create upload task
    let uploadTask: URLSessionUploadTask
    if let resumeData = resumeData {
      if #available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *) {
        uploadTask = session.uploadTask(withResumeData: resumeData)
      } else {
        // Fallback for older versions - restart from beginning
        uploadTask = session.uploadTask(with: urlRequest, fromFile: fileURL)
      }
    } else {
      uploadTask = session.uploadTask(with: urlRequest, fromFile: fileURL)
    }
    
    // Create resumable task wrapper
    let resumableTask = ResumableUploadTask(
      identifier: taskIdentifier,
      uploadTask: uploadTask,
      session: session,
      originalRequest: urlRequest,
      fileURL: fileURL
    )
    
    // Register with delegate for progress tracking
    delegate.registerTask(resumableTask)
    
    // Start the task
    uploadTask.resume()
    
    return resumableTask
  }
}

/// URLSessionDelegate for resumable operations.
private class ResumableSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let tasks = NSLock()
  private var _tasks: [Int: ResumableUploadTask] = [:]
  
  func registerTask(_ task: ResumableUploadTask) {
    tasks.lock()
    // Note: We'd need access to the URLSessionTask's taskIdentifier
    // This is a simplified implementation - would need to be enhanced
    // to properly track tasks by their URLSessionTask identifiers
    tasks.unlock()
  }
  
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    tasks.lock()
    defer { tasks.unlock() }
    
    if let resumableTask = _tasks[task.taskIdentifier] {
      if let error = error as? URLError,
         error.code == .cancelled,
         let resumeData = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
        
        // Store resume data for later use
        ResumeDataManager.shared.storeResumeData(resumeData, for: resumableTask.identifier)
      }
      
      _tasks.removeValue(forKey: task.taskIdentifier)
    }
  }
  
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    tasks.lock()
    defer { tasks.unlock() }
    
    if let resumableTask = _tasks[task.taskIdentifier] {
      resumableTask.progress.totalUnitCount = totalBytesExpectedToSend
      resumableTask.progress.completedUnitCount = totalBytesSent
    }
  }
}