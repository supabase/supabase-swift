//
//  HTTPSession.swift
//
//
//  Created by Claude Code on 26/02/26.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Protocol for HTTP session operations with support for streaming, progress tracking, and background transfers.
///
/// This protocol extends the basic HTTP client functionality to support modern networking patterns
/// including streaming responses, upload/download progress callbacks, and background transfers.
public protocol HTTPSession: Sendable {
  /// Standard request/response operation.
  ///
  /// - Parameter request: The HTTP request to send.
  /// - Returns: The HTTP response containing data and metadata.
  /// - Throws: An error if the request fails.
  func send(_ request: HTTPRequest) async throws -> HTTPResponse

  /// Streaming response operation.
  ///
  /// - Parameter request: The HTTP request to send.
  /// - Returns: A streaming response that yields data chunks as they arrive.
  /// - Throws: An error if the request fails.
  func sendStreaming(_ request: HTTPRequest) async throws -> HTTPStreamingResponse

  /// Upload data with optional progress tracking.
  ///
  /// - Parameters:
  ///   - request: The HTTP request to send.
  ///   - data: The data to upload.
  ///   - progress: Optional callback to track upload progress (bytes sent, total bytes).
  /// - Returns: The HTTP response after upload completes.
  /// - Throws: An error if the upload fails.
  func upload(
    _ request: HTTPRequest,
    from data: Data,
    progress: (@Sendable (Int64, Int64) -> Void)?
  ) async throws -> HTTPResponse

  /// Upload from file URL with optional progress tracking.
  ///
  /// This method streams the file without loading it entirely into memory.
  ///
  /// - Parameters:
  ///   - request: The HTTP request to send.
  ///   - fileURL: The URL of the file to upload.
  ///   - progress: Optional callback to track upload progress (bytes sent, total bytes).
  /// - Returns: The HTTP response after upload completes.
  /// - Throws: An error if the upload fails.
  func upload(
    _ request: HTTPRequest,
    fromFile fileURL: URL,
    progress: (@Sendable (Int64, Int64) -> Void)?
  ) async throws -> HTTPResponse

  /// Download with optional progress tracking.
  ///
  /// - Parameters:
  ///   - request: The HTTP request to send.
  ///   - progress: Optional callback to track download progress (bytes received, total bytes).
  /// - Returns: The download response containing data and metadata.
  /// - Throws: An error if the download fails.
  func download(
    _ request: HTTPRequest,
    progress: (@Sendable (Int64, Int64) -> Void)?
  ) async throws -> HTTPDownloadResponse

  #if !os(Linux) && !os(Windows) && !os(Android)
    /// Upload from file in the background (Darwin platforms only).
    ///
    /// Background uploads continue even when the app is backgrounded or terminated.
    ///
    /// - Parameters:
    ///   - request: The HTTP request to send.
    ///   - fileURL: The URL of the file to upload.
    ///   - sessionIdentifier: Unique identifier for the background session.
    /// - Returns: A background task that can be monitored and controlled.
    /// - Throws: An error if the upload fails to start.
    @available(macOS 11.0, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    func uploadInBackground(
      _ request: HTTPRequest,
      fromFile fileURL: URL,
      sessionIdentifier: String
    ) async throws -> HTTPBackgroundTask

    /// Download to file in the background (Darwin platforms only).
    ///
    /// Background downloads continue even when the app is backgrounded or terminated.
    ///
    /// - Parameters:
    ///   - request: The HTTP request to send.
    ///   - fileURL: The destination URL for the downloaded file.
    ///   - sessionIdentifier: Unique identifier for the background session.
    /// - Returns: A background task that can be monitored and controlled.
    /// - Throws: An error if the download fails to start.
    @available(macOS 11.0, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    func downloadInBackground(
      _ request: HTTPRequest,
      toFile fileURL: URL,
      sessionIdentifier: String
    ) async throws -> HTTPBackgroundTask
  #endif

  /// Access to underlying URLSession for WebSocket support.
  ///
  /// This property is used by the Realtime module to create WebSocket connections
  /// using the same URLSession instance, enabling features like certificate pinning.
  var underlyingURLSession: URLSession { get }
}
