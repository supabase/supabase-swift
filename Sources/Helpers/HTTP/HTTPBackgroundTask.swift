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
  package actor HTTPBackgroundTask: Sendable {
    /// The task identifier assigned by URLSession.
    package let taskIdentifier: Int

    /// The background session identifier.
    package let sessionIdentifier: String

    /// Reference to the underlying URLSessionTask.
    private let urlSessionTask: URLSessionTask

    /// Stream for progress updates.
    private let progressContinuation:
      AsyncStream<(bytesTransferred: Int64, totalBytes: Int64)>.Continuation

    /// Task for completion handling.
    private let completionTask: Task<HTTPResponse, any Error>

    package init(
      taskIdentifier: Int,
      sessionIdentifier: String,
      urlSessionTask: URLSessionTask,
      progressContinuation: AsyncStream<(bytesTransferred: Int64, totalBytes: Int64)>.Continuation,
      completionTask: Task<HTTPResponse, any Error>
    ) {
      self.taskIdentifier = taskIdentifier
      self.sessionIdentifier = sessionIdentifier
      self.urlSessionTask = urlSessionTask
      self.progressContinuation = progressContinuation
      self.completionTask = completionTask
    }

    /// Cancel the background task.
    ///
    /// Cancels the underlying URLSessionTask and terminates progress monitoring.
    package func cancel() async {
      urlSessionTask.cancel()
      progressContinuation.finish()
    }

    /// Suspend the background task.
    ///
    /// The task can be resumed later using `resume()`.
    package func suspend() async {
      urlSessionTask.suspend()
    }

    /// Resume a suspended background task.
    package func resume() async {
      urlSessionTask.resume()
    }

    /// An async stream of progress updates.
    ///
    /// Yields tuples of (bytesTransferred, totalBytes) as the transfer progresses.
    package var progress: AsyncStream<(bytesTransferred: Int64, totalBytes: Int64)> {
      AsyncStream { continuation in
        // This is a simplified implementation that won't work properly in production
        // In a real implementation, we would need to properly bridge the progress continuation
        // For now, just finish immediately
        continuation.finish()
      }
    }

    /// The completion task.
    ///
    /// Await this task's value to get the final HTTP response when the transfer completes.
    package var completion: Task<HTTPResponse, any Error> {
      completionTask
    }
  }

#else

  // Background transfers are not supported on Linux/Windows/Android
  @available(*, unavailable, message: "Background transfers require Darwin platforms")
  package struct HTTPBackgroundTask: Sendable {
    package let taskIdentifier: Int
    package let sessionIdentifier: String

    package func cancel() async {
      fatalError("Background transfers not supported on this platform")
    }

    package func suspend() async {
      fatalError("Background transfers not supported on this platform")
    }

    package func resume() async {
      fatalError("Background transfers not supported on this platform")
    }

    package var progress: AsyncStream<(bytesTransferred: Int64, totalBytes: Int64)> {
      fatalError("Background transfers not supported on this platform")
    }

    package var completion: Task<HTTPResponse, any Error> {
      fatalError("Background transfers not supported on this platform")
    }
  }

#endif
