import Foundation
import HTTPTypes
import HTTPTypesFoundation
import OpenAPIRuntime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A URLSession-based transport that supports streaming operations.
package struct StreamingURLSessionTransport: StreamingClientTransport {
  private let session: URLSession
  private let delegate: StreamingSessionDelegate
  
  package init(configuration: URLSessionConfiguration? = nil) {
    let config = configuration ?? {
      let c = URLSessionConfiguration.default
      c.timeoutIntervalForRequest = 0 // No timeout for streaming
      c.allowsCellularAccess = true
      c.waitsForConnectivity = true
      return c
    }()
    
    self.delegate = StreamingSessionDelegate()
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
  
  // MARK: - StreamingClientTransport
  
  package func sendStreaming(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    progressHandler: @escaping @Sendable (Progress) -> Void
  ) async throws -> (HTTPTypes.HTTPResponse, AsyncThrowingStream<Data, any Error>) {
    guard var urlRequest = URLRequest(httpRequest: request) else {
      throw URLError(.badURL)
    }
    
    // Resolve relative URLs against baseURL
    if let url = urlRequest.url, url.scheme == nil {
      urlRequest.url = URL(string: url.path, relativeTo: baseURL)
    }
    
    // Handle request body
    if let body = body {
      urlRequest.httpBody = try await Data(collecting: body, upTo: .max)
    }
    
    // Check availability for streaming
    if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
      // Create data task for streaming
      let (asyncBytes, response) = try await session.bytes(for: urlRequest)
      
      guard let httpURLResponse = response as? HTTPURLResponse,
            let httpResponse = httpURLResponse.httpResponse else {
        throw URLError(.badServerResponse)
      }
      
      // Create progress object
      let progress = Progress()
      if let contentLength = httpURLResponse.value(forHTTPHeaderField: "Content-Length"),
         let totalBytes = Int64(contentLength) {
        progress.totalUnitCount = totalBytes
      }
      
      // Create streaming response
      let stream = AsyncThrowingStream<Data, any Error> { continuation in
        Task {
          do {
            var bytesReceived: Int64 = 0
            var buffer = Data()
            
            for try await byte in asyncBytes {
              buffer.append(byte)
              bytesReceived += 1
              
              // Update progress
              if progress.totalUnitCount > 0 {
                progress.completedUnitCount = bytesReceived
                progressHandler(progress)
              }
              
              // Yield chunks of reasonable size (1KB)
              if buffer.count >= 1024 {
                continuation.yield(buffer)
                buffer = Data()
              }
            }
            
            // Yield remaining data
            if !buffer.isEmpty {
              continuation.yield(buffer)
            }
            
            continuation.finish()
          } catch {
            continuation.finish(throwing: error)
          }
        }
      }
      
      return (httpResponse, stream)
    } else {
      // Fallback for older versions - use regular data task
      let (data, urlResponse) = try await session.data(for: urlRequest)
      guard let httpURLResponse = urlResponse as? HTTPURLResponse,
            let httpResponse = httpURLResponse.httpResponse else {
        throw URLError(.badServerResponse)
      }
      
      // Create progress and update it
      let progress = Progress()
      progress.totalUnitCount = Int64(data.count)
      progress.completedUnitCount = Int64(data.count)
      progressHandler(progress)
      
      return (httpResponse, AsyncThrowingStream { continuation in
        continuation.yield(data)
        continuation.finish()
      })
    }
  }
}

/// URLSessionDelegate for streaming operations.
private class StreamingSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  
  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    // Data is handled through AsyncSequence in iOS 15+
    // This delegate method is for compatibility if needed
  }
  
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    // Handle task completion if needed
  }
}