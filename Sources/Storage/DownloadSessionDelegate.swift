//
//  DownloadSessionDelegate.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import ConcurrencyExtras
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Callbacks registered for a single `URLSessionDownloadTask`.
///
/// The delegate calls `onFinished` on successful completion and `onCompleteWithError` on
/// failure or explicit cancellation. Both are one-shot: the delegate unregisters the callbacks
/// as soon as either fires.
struct DownloadTaskCallbacks: Sendable {
  /// Periodic bytes-received update. `totalBytesWritten` is the running total;
  /// `totalBytesExpectedToWrite` is the `Content-Length` (-1 if unknown).
  let onProgress: @Sendable (_ totalBytesWritten: Int64, _ totalBytesExpectedToWrite: Int64) -> Void
  /// The download finished. The delegate moves the temporary file to a stable location
  /// synchronously (before URLSession reclaims it) and passes the result here.
  let onFinished: @Sendable (Result<URL, StorageError>) -> Void
  /// Called on failure or cancellation. `nil` is never passed (success is delivered via
  /// `onFinished`); the parameter is nullable only to match the delegate signature.
  let onCompleteWithError: @Sendable (_ error: (any Error)?) -> Void
}

final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, Sendable {

  struct MutableState {
    var callbacks: [Int: DownloadTaskCallbacks] = [:]
    var backgroundCompletionHandler: (@Sendable () -> Void)?
  }

  private let state = LockIsolated(MutableState())

  // MARK: - Registration

  func register(taskIdentifier: Int, callbacks: DownloadTaskCallbacks) {
    state.withValue { $0.callbacks[taskIdentifier] = callbacks }
  }

  // MARK: - Task creation

  /// Creates a `StorageDownloadTask` backed by a `DownloadEngine`.
  ///
  /// `buildRequest` is called asynchronously before the underlying
  /// `URLSessionDownloadTask` is created, so callers can fetch an auth token
  /// without blocking.
  func makeStorageDownloadTask(
    in session: URLSession,
    buildRequest: @escaping @Sendable () async throws -> URLRequest
  ) -> StorageDownloadTask {
    DownloadEngine.makeTask(session: session, delegate: self, requestBuilder: buildRequest)
  }

  /// Package-level access for tests to drive delegate callbacks directly.
  ///
  /// Returns the stream and underlying `URLSessionDownloadTask` so tests can call
  /// delegate methods directly without going through a real network connection.
  package func makeDownloadTask(
    in session: URLSession,
    request: URLRequest
  ) -> (
    stream: AsyncStream<TransferEvent<URL>>,
    eventsContinuation: AsyncStream<TransferEvent<URL>>.Continuation,
    task: URLSessionDownloadTask
  ) {
    let (eventStream, eventsContinuation) = AsyncStream<TransferEvent<URL>>.makeStream()
    let urlTask = session.downloadTask(with: request)

    register(
      taskIdentifier: urlTask.taskIdentifier,
      callbacks: DownloadTaskCallbacks(
        onProgress: { totalBytesWritten, totalBytesExpectedToWrite in
          eventsContinuation.yield(
            .progress(
              TransferProgress(
                bytesTransferred: totalBytesWritten,
                totalBytes: totalBytesExpectedToWrite
              )))
        },
        onFinished: { result in
          switch result {
          case .success(let url):
            eventsContinuation.yield(.completed(url))
          case .failure(let error):
            eventsContinuation.yield(.failed(error))
          }
          eventsContinuation.finish()
        },
        onCompleteWithError: { error in
          guard let error else { return }
          let storageError: StorageError =
            (error as? URLError)?.code == .cancelled
            ? .cancelled
            : .networkError(underlying: error)
          eventsContinuation.yield(.failed(storageError))
          eventsContinuation.finish()
        }
      )
    )

    return (eventStream, eventsContinuation, urlTask)
  }

  func setBackgroundCompletionHandler(_ handler: @escaping @Sendable () -> Void) {
    state.withValue { $0.backgroundCompletionHandler = handler }
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    state.withValue {
      $0.callbacks[downloadTask.taskIdentifier]
    }?.onProgress(totalBytesWritten, totalBytesExpectedToWrite)
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    // URLSession deletes `location` as soon as this method returns, so we must move
    // the file synchronously here — before invoking the callback or doing anything async.
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let moveResult: Result<URL, StorageError>
    do {
      try FileManager.default.moveItem(at: location, to: destination)
      moveResult = .success(destination)
    } catch {
      moveResult = .failure(StorageError.fileSystemError(underlying: error))
    }

    // Unregister before calling the callback — the engine marks the task terminal on
    // receipt, so subsequent delegate calls should be no-ops.
    let callbacks = state.withValue {
      let cb = $0.callbacks[downloadTask.taskIdentifier]
      $0.callbacks.removeValue(forKey: downloadTask.taskIdentifier)
      return cb
    }
    callbacks?.onFinished(moveResult)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    guard let error else { return }
    // Only unregister on error — success is handled (and unregistered) by
    // urlSession(_:downloadTask:didFinishDownloadingTo:) which fires first.
    let callbacks = state.withValue {
      let cb = $0.callbacks[task.taskIdentifier]
      $0.callbacks.removeValue(forKey: task.taskIdentifier)
      return cb
    }
    callbacks?.onCompleteWithError(error)
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    state.withValue {
      $0.backgroundCompletionHandler?()
      $0.backgroundCompletionHandler = nil
    }
  }
}
