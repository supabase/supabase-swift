//
//  StorageTransferTask.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import Foundation

/// A handle to an in-flight upload or download.
///
/// Tasks start immediately on creation and are `@discardableResult` — fire-and-forget works
/// without holding a reference. Hold the task to observe progress or control execution.
///
/// Both `.events` and `.value` are independent: consuming one does not affect the other.
public final class StorageTransferTask<Success: Sendable>: Sendable {

  /// A stream of transfer events. Finishes after `.completed` or `.failed`.
  public let events: AsyncStream<TransferEvent<Success>>

  private let _resultTask: Task<Success, any Error>
  private let _pause: @Sendable () async -> Void
  private let _resume: @Sendable () async -> Void
  private let _cancel: @Sendable () async -> Void

  init(
    events: AsyncStream<TransferEvent<Success>>,
    resultTask: Task<Success, any Error>,
    pause: @Sendable @escaping () async -> Void,
    resume: @Sendable @escaping () async -> Void,
    cancel: @Sendable @escaping () async -> Void
  ) {
    self.events = events
    self._resultTask = resultTask
    self._pause = pause
    self._resume = resume
    self._cancel = cancel
  }

  /// The transfer outcome as a `Result`. Never throws — inspect `.success` / `.failure` directly.
  /// Safe for concurrent callers — backed by `Task.result`.
  public var result: Result<Success, any Error> {
    get async { await _resultTask.result }
  }

  /// Awaits the success value. Throws `StorageError` on failure or cancellation.
  /// Safe for concurrent callers — backed by `Task.value`.
  public var value: Success {
    get async throws { try await result.get() }
  }

  /// Suspends the transfer. For uploads: completes the current in-flight chunk first.
  public func pause() async { await _pause() }

  /// Resumes a paused transfer. For uploads: HEADs the server to re-sync offset first.
  public func resume() async { await _resume() }

  /// Cancels the transfer immediately.
  public func cancel() async {
    await _cancel()
    _resultTask.cancel()
  }
}

extension StorageTransferTask {
  /// Returns a new task that applies `transform` to the success value.
  /// Progress events pass through unchanged. Pause/resume/cancel delegate to `self`.
  func mapResult<NewSuccess: Sendable>(
    _ transform: @Sendable @escaping (Success) throws -> NewSuccess
  ) -> StorageTransferTask<NewSuccess> {
    let (newStream, newContinuation) = AsyncStream<TransferEvent<NewSuccess>>.makeStream()
    let (resultStream, resultContinuation) = AsyncStream<Result<NewSuccess, any Error>>.makeStream(
      bufferingPolicy: .bufferingNewest(1))

    let bridgeTask = Task {
      for await event in self.events {
        switch event {
        case .progress(let p):
          newContinuation.yield(.progress(p))
        case .completed(let value):
          do {
            let mapped = try transform(value)
            newContinuation.yield(.completed(mapped))
            newContinuation.finish()
            resultContinuation.yield(.success(mapped))
            resultContinuation.finish()
          } catch {
            let storageError = StorageError.fileSystemError(underlying: error)
            newContinuation.yield(.failed(storageError))
            newContinuation.finish()
            resultContinuation.yield(.failure(storageError))
            resultContinuation.finish()
          }
        case .failed(let error):
          newContinuation.yield(.failed(error))
          newContinuation.finish()
          resultContinuation.yield(.failure(error))
          resultContinuation.finish()
        }
      }
      newContinuation.finish()
    }

    let newResultTask = Task<NewSuccess, any Error> {
      for await r in resultStream { return try r.get() }
      throw StorageError.cancelled
    }

    return StorageTransferTask<NewSuccess>(
      events: newStream,
      resultTask: newResultTask,
      pause: self._pause,
      resume: self._resume,
      cancel: {
        await self._cancel()
        bridgeTask.cancel()
      }
    )
  }
}

/// An event emitted during a transfer.
public enum TransferEvent<Success: Sendable>: Sendable {
  case progress(TransferProgress)
  /// Terminal — the stream ends after this event.
  case completed(Success)
  /// Terminal — the stream ends after this event.
  case failed(StorageError)
}

/// Byte-level progress for a transfer.
public struct TransferProgress: Sendable {
  public let bytesTransferred: Int64
  public let totalBytes: Int64

  public var fractionCompleted: Double {
    guard totalBytes > 0 else { return 0 }
    return Double(bytesTransferred) / Double(totalBytes)
  }
}

/// A handle for an upload. Success type is ``FileUploadResponse``.
public typealias StorageUploadTask = StorageTransferTask<FileUploadResponse>

/// A handle for a download. Success type is `URL` — a path to the downloaded file on disk.
public typealias StorageDownloadTask = StorageTransferTask<URL>
