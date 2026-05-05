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

final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, Sendable {

  struct DownloadTaskState {
    let eventsContinuation: AsyncStream<TransferEvent<URL>>.Continuation
    let resultContinuation: AsyncStream<Result<URL, any Error>>.Continuation
  }

  struct MutableState {
    var tasks: [Int: DownloadTaskState] = [:]
    var backgroundCompletionHandler: (@Sendable () -> Void)?
  }

  private let state = LockIsolated(MutableState())

  // MARK: - Task creation

  /// Creates a `StorageDownloadTask` backed by this delegate for the given request.
  /// The underlying `URLSessionDownloadTask` is resumed immediately.
  func makeStorageDownloadTask(in session: URLSession, request: URLRequest) -> StorageDownloadTask {
    let (eventStream, eventsContinuation) = AsyncStream<TransferEvent<URL>>.makeStream()
    let (resultStream, resultContinuation) = AsyncStream<Result<URL, any Error>>.makeStream(
      bufferingPolicy: .bufferingNewest(1))

    let urlTask = session.downloadTask(with: request)

    state.withValue {
      $0.tasks[urlTask.taskIdentifier] = DownloadTaskState(
        eventsContinuation: eventsContinuation,
        resultContinuation: resultContinuation
      )
    }

    eventsContinuation.onTermination = { reason in
      guard case .cancelled = reason else { return }
      urlTask.cancel()
    }

    let resultTask = Task<URL, any Error> {
      for await r in resultStream { return try r.get() }
      throw StorageError.cancelled
    }

    let storageTask = StorageDownloadTask(
      events: eventStream,
      resultTask: resultTask,
      pause: { urlTask.suspend() },
      resume: { urlTask.resume() },
      cancel: { urlTask.cancel() }
    )

    urlTask.resume()
    return storageTask
  }

  /// Package-level access for tests to drive delegate callbacks directly.
  package func makeDownloadTask(
    in session: URLSession,
    request: URLRequest
  ) -> (
    stream: AsyncStream<TransferEvent<URL>>,
    eventsContinuation: AsyncStream<TransferEvent<URL>>.Continuation,
    task: URLSessionDownloadTask
  ) {
    let (eventStream, eventsContinuation) = AsyncStream<TransferEvent<URL>>.makeStream()
    let (resultStream, resultContinuation) = AsyncStream<Result<URL, any Error>>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let urlTask = session.downloadTask(with: request)
    state.withValue {
      $0.tasks[urlTask.taskIdentifier] = DownloadTaskState(
        eventsContinuation: eventsContinuation,
        resultContinuation: resultContinuation
      )
    }
    _ = resultStream  // satisfy unused warning — test uses stream directly via delegate callbacks
    _ = resultContinuation
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
      guard let taskState = $0.tasks[downloadTask.taskIdentifier] else { return }
      taskState.eventsContinuation.yield(
        .progress(
          TransferProgress(
            bytesTransferred: totalBytesWritten,
            totalBytes: totalBytesExpectedToWrite
          )))
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    state.withValue {
      guard let taskState = $0.tasks[downloadTask.taskIdentifier] else { return }

      let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)

      do {
        try FileManager.default.moveItem(at: location, to: destination)
        taskState.eventsContinuation.yield(.completed(destination))
        taskState.eventsContinuation.finish()
        taskState.resultContinuation.yield(.success(destination))
        taskState.resultContinuation.finish()
      } catch {
        let storageError = StorageError.fileSystemError(underlying: error)
        taskState.eventsContinuation.yield(.failed(storageError))
        taskState.eventsContinuation.finish()
        taskState.resultContinuation.yield(.failure(storageError))
        taskState.resultContinuation.finish()
      }
      $0.tasks.removeValue(forKey: downloadTask.taskIdentifier)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    guard let error else { return }

    state.withValue {
      guard let taskState = $0.tasks[task.taskIdentifier] else { return }

      let storageError: StorageError
      if (error as? URLError)?.code == .cancelled {
        storageError = .cancelled
      } else {
        storageError = .networkError(underlying: error)
      }

      taskState.eventsContinuation.yield(.failed(storageError))
      taskState.eventsContinuation.finish()
      taskState.resultContinuation.yield(.failure(storageError))
      taskState.resultContinuation.finish()
      $0.tasks.removeValue(forKey: task.taskIdentifier)
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    state.withValue {
      $0.backgroundCompletionHandler?()
      $0.backgroundCompletionHandler = nil
    }
  }
}
