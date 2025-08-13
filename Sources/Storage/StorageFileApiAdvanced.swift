import Foundation
import HTTPTypes
import Helpers

/// Advanced storage file API with streaming, background, and resumable capabilities.
public class StorageFileApiAdvanced: StorageFileApi, @unchecked Sendable {
  private let streamingClient: Helpers.Client?
  private let backgroundClient: Helpers.Client?
  private let resumableClient: Helpers.Client?
  private let enhancedConfiguration: EnhancedStorageClientConfiguration
  
  /// Creates a new advanced storage file API.
  /// - Parameters:
  ///   - bucketId: The bucket identifier.
  ///   - configuration: The enhanced storage configuration.
  ///   - standardClient: The standard HTTP client.
  ///   - streamingClient: The streaming HTTP client (optional).
  ///   - backgroundClient: The background HTTP client (optional).
  ///   - resumableClient: The resumable HTTP client (optional).
  package init(
    bucketId: String,
    configuration: EnhancedStorageClientConfiguration,
    standardClient: Helpers.Client,
    streamingClient: Helpers.Client?,
    backgroundClient: Helpers.Client?,
    resumableClient: Helpers.Client?
  ) {
    self.streamingClient = streamingClient
    self.backgroundClient = backgroundClient
    self.resumableClient = resumableClient
    self.enhancedConfiguration = configuration
    
    super.init(bucketId: bucketId, configuration: configuration.base)
  }
}

// MARK: - Streaming Upload Methods

public extension StorageFileApiAdvanced {
  
  /// Uploads a file with streaming support and real-time progress tracking.
  /// - Parameters:
  ///   - path: The file path in the bucket.
  ///   - fileURL: The local file URL to upload.
  ///   - options: Upload options (cache control, content type, etc.).
  ///   - progressHandler: Called with progress updates (0.0 to 1.0).
  /// - Returns: An async stream that yields upload progress and final response.
  func uploadStreaming(
    _ path: String,
    fileURL: URL,
    options: FileOptions = FileOptions(),
    progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
  ) -> AsyncThrowingStream<StreamingUploadProgress, any Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          guard let streamingClient = self.streamingClient else {
            throw StorageError.streamingNotEnabled
          }
          
          guard fileURL.isFileURL && FileManager.default.fileExists(atPath: fileURL.path) else {
            throw StorageError.invalidFileURL
          }
          
          let cleanPath = _removeEmptyFolders(path)
          let finalPath = _getFinalPath(cleanPath)
          
          // Build multipart form data
          let formData = MultipartFormData()
          formData.append(
            options.cacheControl.data(using: .utf8)!,
            withName: "cacheControl"
          )
          
          if let metadata = options.metadata {
            formData.append(encodeMetadata(metadata), withName: "metadata")
          }
          
          formData.append(fileURL, withName: "")
          
          // Create HTTP request
          let requestURL = configuration.url.appendingPathComponent("object/\(finalPath)")
          var request = HTTPTypes.HTTPRequest(method: .post, url: requestURL)
          request.headerFields[.contentType] = formData.contentType
          
          // Add bucket headers
          var headers = HTTPFields(configuration.headers)
          headers[.authorization] = headers[.authorization] ?? "Bearer \(configuration.headers["apikey"] ?? "")"
          request.headerFields = headers.merging(with: request.headerFields)
          
          // Send streaming request - cast transport to streaming type
          guard let streamingTransport = streamingClient.transport as? StreamingURLSessionTransport else {
            throw StorageError.streamingNotEnabled
          }
          
          let (response, dataStream) = try await streamingTransport.sendStreaming(
            request,
            body: HTTPBody(try formData.encode()),
            baseURL: configuration.url,
            operationID: "upload",
            progressHandler: { progress in
              let fractionCompleted = progress.fractionCompleted
              progressHandler(fractionCompleted)
              continuation.yield(.progress(fractionCompleted))
            }
          )
          
          guard (200..<300).contains(response.status.code) else {
            // Collect error data
            var errorData = Data()
            for try await chunk in dataStream {
              errorData.append(chunk)
            }
            
            if let error = try? configuration.decoder.decode(StorageError.self, from: errorData) {
              throw error
            }
            throw StorageError(
              message: "Upload failed with status code \(response.status.code)",
              error: String(data: errorData, encoding: .utf8) ?? "UnknownError"
            )
          }
          
          // Collect response data
          var responseData = Data()
          for try await chunk in dataStream {
            responseData.append(chunk)
          }
          
          let uploadResponse = try configuration.decoder.decode(StorageUploadResponse.self, from: responseData)
          let result = FileUploadResponse(
            id: uploadResponse.Id,
            path: path,
            fullPath: uploadResponse.Key
          )
          
          continuation.yield(.completed(result))
          continuation.finish()
          
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }
  
  /// Downloads a file with streaming support and progress tracking.
  /// - Parameters:
  ///   - path: The file path to download.
  ///   - options: Transform options for the download.
  ///   - progressHandler: Called with progress updates (0.0 to 1.0).
  /// - Returns: An async stream of data chunks.
  func downloadStreaming(
    _ path: String,
    options: TransformOptions? = nil,
    progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
  ) -> AsyncThrowingStream<Data, any Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          guard let streamingClient = self.streamingClient else {
            throw StorageError.streamingNotEnabled
          }
          
          let cleanPath = _removeEmptyFolders(path)
          let finalPath = _getFinalPath(cleanPath)
          
          // Create HTTP request
          let requestURL = configuration.url.appendingPathComponent("object/\(finalPath)")
          var request = HTTPTypes.HTTPRequest(method: .get, url: requestURL)
          
          // Add query parameters for transform options
          if let options = options,
             var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) {
            components.queryItems = options.queryItems
            if let newURL = components.url {
              request = HTTPTypes.HTTPRequest(method: .get, url: newURL)
            }
          }
          
          // Add bucket headers
          var headers = HTTPFields(configuration.headers)
          headers[.authorization] = headers[.authorization] ?? "Bearer \(configuration.headers["apikey"] ?? "")"
          request.headerFields = headers
          
          // Send streaming request - cast transport to streaming type
          guard let streamingTransport = streamingClient.transport as? StreamingURLSessionTransport else {
            throw StorageError.streamingNotEnabled
          }
          
          let (response, dataStream) = try await streamingTransport.sendStreaming(
            request,
            body: nil,
            baseURL: configuration.url,
            operationID: "download",
            progressHandler: { progress in
              progressHandler(progress.fractionCompleted)
            }
          )
          
          guard (200..<300).contains(response.status.code) else {
            // Collect error data
            var errorData = Data()
            for try await chunk in dataStream {
              errorData.append(chunk)
            }
            
            if let error = try? configuration.decoder.decode(StorageError.self, from: errorData) {
              throw error
            }
            throw StorageError(
              message: "Download failed with status code \(response.status.code)",
              error: String(data: errorData, encoding: .utf8) ?? "UnknownError"
            )
          }
          
          // Stream data chunks to caller
          for try await chunk in dataStream {
            continuation.yield(chunk)
          }
          
          continuation.finish()
          
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }
  
  /// Downloads a file directly to a local file URL with progress tracking.
  /// - Parameters:
  ///   - path: The file path to download.
  ///   - destinationURL: Local file URL where the downloaded file will be saved.
  ///   - options: Transform options for the download.
  ///   - progressHandler: Called with progress updates (0.0 to 1.0).
  func downloadToFile(
    _ path: String,
    destinationURL: URL,
    options: TransformOptions? = nil,
    progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
  ) async throws {
    // Create destination directory if needed
    let parentDirectory = destinationURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: parentDirectory,
      withIntermediateDirectories: true,
      attributes: nil
    )
    
    // Create file handle for writing
    FileManager.default.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)
    let fileHandle = try FileHandle(forWritingTo: destinationURL)
    defer { fileHandle.closeFile() }
    
    // Stream data directly to file
    for try await chunk in downloadStreaming(path, options: options, progressHandler: progressHandler) {
      fileHandle.write(chunk)
    }
  }
}

// MARK: - Background Upload Methods

public extension StorageFileApiAdvanced {
  
  /// Uploads a file in the background, surviving app lifecycle changes.
  /// - Parameters:
  ///   - path: The file path in the bucket.
  ///   - fileURL: The local file URL to upload.
  ///   - options: Upload options (cache control, content type, etc.).
  ///   - taskIdentifier: Unique identifier for this background task.
  /// - Returns: A background upload task that can be monitored and controlled.
  func uploadInBackground(
    _ path: String,
    fileURL: URL,
    options: FileOptions = FileOptions(),
    taskIdentifier: String = UUID().uuidString
  ) async throws -> BackgroundUploadTask {
    guard let backgroundClient = self.backgroundClient else {
      throw StorageError.backgroundUploadsNotEnabled
    }
    
    guard fileURL.isFileURL && FileManager.default.fileExists(atPath: fileURL.path) else {
      throw StorageError.invalidFileURL
    }
    
    let cleanPath = _removeEmptyFolders(path)
    let finalPath = _getFinalPath(cleanPath)
    
    // Create HTTP request
    let requestURL = configuration.url.appendingPathComponent("object/\(finalPath)")
    var request = HTTPTypes.HTTPRequest(method: .post, url: requestURL)
    
    // Add bucket headers
    var headers = HTTPFields(configuration.headers)
    headers[.authorization] = headers[.authorization] ?? "Bearer \(configuration.headers["apikey"] ?? "")"
    request.headerFields = headers
    
    // Cast transport to background type
    guard let backgroundTransport = backgroundClient.transport as? BackgroundURLSessionTransport else {
      throw StorageError.backgroundUploadsNotEnabled
    }
    
    return try await backgroundTransport.sendInBackground(
      request,
      fileURL: fileURL,
      baseURL: configuration.url,
      operationID: "backgroundUpload",
      taskIdentifier: taskIdentifier
    )
  }
}

// MARK: - Resumable Upload Methods

public extension StorageFileApiAdvanced {
  
  /// Uploads a file with resumable capability.
  /// - Parameters:
  ///   - path: The file path in the bucket.
  ///   - fileURL: The local file URL to upload.
  ///   - options: Upload options (cache control, content type, etc.).
  ///   - resumeData: Optional resume data from a previous attempt.
  ///   - maxRetries: Maximum number of retry attempts.
  /// - Returns: A resumable upload task that can be paused and resumed.
  func uploadResumable(
    _ path: String,
    fileURL: URL,
    options: FileOptions = FileOptions(),
    resumeData: Data? = nil,
    maxRetries: Int = 3
  ) async throws -> ResumableUploadTask {
    guard let resumableClient = self.resumableClient else {
      throw StorageError.resumableUploadsNotEnabled
    }
    
    guard fileURL.isFileURL && FileManager.default.fileExists(atPath: fileURL.path) else {
      throw StorageError.invalidFileURL
    }
    
    let cleanPath = _removeEmptyFolders(path)
    let finalPath = _getFinalPath(cleanPath)
    
    // Create HTTP request
    let requestURL = configuration.url.appendingPathComponent("object/\(finalPath)")
    var request = HTTPTypes.HTTPRequest(method: .post, url: requestURL)
    
    // Add bucket headers
    var headers = HTTPFields(configuration.headers)
    headers[.authorization] = headers[.authorization] ?? "Bearer \(configuration.headers["apikey"] ?? "")"
    request.headerFields = headers
    
    // Cast transport to resumable type
    guard let resumableTransport = resumableClient.transport as? ResumableURLSessionTransport else {
      throw StorageError.resumableUploadsNotEnabled
    }
    
    return try await resumableTransport.sendResumable(
      request,
      fileURL: fileURL,
      baseURL: configuration.url,
      operationID: "resumableUpload",
      resumeData: resumeData
    )
  }
}

// MARK: - Supporting Types

/// Represents progress during a streaming upload operation.
public enum StreamingUploadProgress: Sendable {
  /// Upload is in progress with the specified completion fraction (0.0 to 1.0).
  case progress(Double)
  
  /// Upload completed successfully with the response.
  case completed(FileUploadResponse)
}

// MARK: - Private Helper Methods

private extension StorageFileApiAdvanced {
  func _getFinalPath(_ path: String) -> String {
    "\(bucketId)/\(path)"
  }
  
  func _removeEmptyFolders(_ path: String) -> String {
    let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let cleanedPath = trimmedPath.replacingOccurrences(
      of: "/+", with: "/", options: .regularExpression
    )
    return cleanedPath
  }
  
  func encodeMetadata(_ metadata: [String: Any]) -> Data {
    let jsonData = try? JSONSerialization.data(withJSONObject: metadata)
    return jsonData ?? Data()
  }
}

// MARK: - Response Types

private struct StorageUploadResponse: Decodable {
  let Id: String
  let Key: String
}