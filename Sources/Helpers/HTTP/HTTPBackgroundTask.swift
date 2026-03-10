//
//  HTTPBackgroundTask.swift
//
//
//  Created by Claude Code on 26/02/26.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if !os(Linux) && !os(Windows) && !os(Android)

  /// An actor managing a background upload or download task.
  ///
  /// Background tasks continue to run even when the app is backgrounded or terminated.
  /// The system will wake the app when the transfer completes or requires attention.
  ///
  /// Example:
  /// ```swift
  /// let task = try await httpSession.uploadInBackground(
  ///   request,
  ///   fromFile: fileURL,
  ///   sessionIdentifier: "com.myapp.upload"
  /// )
  ///
  /// // Monitor progress
  /// for await (transferred, total) in task.progress {
  ///   print("Progress: \(transferred)/\(total)")
  /// }
  ///
  /// // Wait for completion
  /// let response = try await task.completion.value
  /// ```
  public actor HTTPBackgroundTask: Sendable {
    /// The task identifier assigned by URLSession.
    public let taskIdentifier: Int

    /// The background session identifier.
    public let sessionIdentifier: String

    /// Reference to the underlying URLSessionTask.
    private let urlSessionTask: URLSessionTask

    /// Stream for progress updates.
    private let progressStream: AsyncStream<(bytesTransferred: Int64, totalBytes: Int64)>

    /// Continuation for finishing the progress stream on cancellation.
    private let progressContinuation:
      AsyncStream<(bytesTransferred: Int64, totalBytes: Int64)>.Continuation

    /// Task for completion handling.
    private let completionTask: Task<HTTPResponse, any Error>

    public init(
      taskIdentifier: Int,
      sessionIdentifier: String,
      urlSessionTask: URLSessionTask,
      progressStream: AsyncStream<(bytesTransferred: Int64, totalBytes: Int64)>,
      progressContinuation: AsyncStream<(bytesTransferred: Int64, totalBytes: Int64)>.Continuation,
      completionTask: Task<HTTPResponse, any Error>
    ) {
      self.taskIdentifier = taskIdentifier
      self.sessionIdentifier = sessionIdentifier
      self.urlSessionTask = urlSessionTask
      self.progressStream = progressStream
      self.progressContinuation = progressContinuation
      self.completionTask = completionTask
    }

    /// Cancel the background task.
    ///
    /// Cancels the underlying URLSessionTask and terminates progress monitoring.
    public func cancel() async {
      urlSessionTask.cancel()
      progressContinuation.finish()
    }

    /// Suspend the background task.
    ///
    /// The task can be resumed later using `resume()`.
    public func suspend() async {
      urlSessionTask.suspend()
    }

    /// Resume a suspended background task.
    public func resume() async {
      urlSessionTask.resume()
    }

    /// An async stream of progress updates.
    ///
    /// Yields tuples of (bytesTransferred, totalBytes) as the transfer progresses.
    public var progress: AsyncStream<(bytesTransferred: Int64, totalBytes: Int64)> {
      progressStream
    }

    /// The completion task.
    ///
    /// Await this task's value to get the final HTTP response when the transfer completes.
    public var completion: Task<HTTPResponse, any Error> {
      completionTask
    }
  }

#else

  // Background transfers are not supported on Linux/Windows/Android
  @available(*, unavailable, message: "Background transfers require Darwin platforms")
  public struct HTTPBackgroundTask: Sendable {
    public let taskIdentifier: Int
    public let sessionIdentifier: String

    public func cancel() async {
      fatalError("Background transfers not supported on this platform")
    }

    public func suspend() async {
      fatalError("Background transfers not supported on this platform")
    }

    public func resume() async {
      fatalError("Background transfers not supported on this platform")
    }

    public var progress: AsyncStream<(bytesTransferred: Int64, totalBytes: Int64)> {
      fatalError("Background transfers not supported on this platform")
    }

    public var completion: Task<HTTPResponse, any Error> {
      fatalError("Background transfers not supported on this platform")
    }
  }

#endif
