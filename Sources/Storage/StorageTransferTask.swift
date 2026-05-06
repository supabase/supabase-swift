//
//  StorageTransferTask.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import Foundation

/// A handle to an in-flight upload or download.
///
/// ## Usage patterns
///
/// **Fire and forget**
/// ```swift
/// storage.from("avatars").upload("user.jpg", data: imageData)
/// ```
///
/// **Await the result**
/// ```swift
/// let response = try await storage.from("avatars")
///   .upload("user.jpg", data: imageData)
///   .value
/// ```
///
/// **Observe progress**
/// ```swift
/// let task = storage.from("avatars").upload("user.jpg", data: imageData)
/// for await event in task.events {
///   switch event {
///   case .progress(let p):
///     updateProgressBar(p.fractionCompleted)
///   case .completed(let response):
///     print("Uploaded to \(response.fullPath)")
///   case .failed(let error):
///     print("Upload failed: \(error.message)")
///   }
/// }
/// ```
///
/// **Pause, resume, and cancel (TUS uploads only)**
/// ```swift
/// let task = storage.from("videos").uploadResumable("clip.mp4", fileURL: fileURL)
/// await task.pause()   // suspend mid-upload
/// await task.resume()  // continue from where it left off
/// await task.cancel()  // abort entirely
/// ```
///
/// Both ``events`` and ``value`` are independent: consuming one does not affect the other.
public final class StorageTransferTask<Success: Sendable>: Sendable {

  /// A stream of transfer lifecycle events.
  ///
  /// Emits ``TransferEvent/progress(_:)`` events while the transfer is active, then terminates
  /// with either ``TransferEvent/completed(_:)`` or ``TransferEvent/failed(_:)``.
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
  public var result: Result<Success, any Error> {
    get async { await _resultTask.result }
  }

  /// Awaits the success value. Throws `StorageError` on failure or cancellation.
  public var value: Success {
    get async throws { try await result.get() }
  }

  /// Suspends the transfer.
  ///
  /// Only supported for TUS (resumable) uploads. For multipart uploads this is a no-op —
  /// use ``cancel()`` and re-upload from scratch if you need to stop a multipart transfer.
  /// For TUS uploads the current in-flight chunk is drained before the task suspends.
  public func pause() async { await _pause() }

  /// Resumes a previously paused transfer.
  ///
  /// Only supported for TUS (resumable) uploads. For multipart uploads this is a no-op.
  /// For TUS uploads the server is HEAD-queried to re-sync the byte offset before uploading resumes.
  public func resume() async { await _resume() }

  /// Cancels the transfer immediately.
  ///
  /// Cancelling a transfer that has already completed or failed is a no-op.
  /// After cancellation, ``value`` throws a ``StorageError`` with code ``StorageErrorCode/cancelled``,
  /// and the ``events`` stream ends with a ``TransferEvent/failed(_:)`` event.
  public func cancel() async {
    // Order is load-bearing: _cancel() must run first.
    // It sets the engine's state to .cancelled and finishes the continuations before
    // Swift's structured cancellation propagates. If _resultTask.cancel() fired first,
    // the resulting CancellationError would reach handleRunError while the engine is
    // still in .uploading/.creating, causing it to call cancel() a second time and
    // race with this explicit cancellation path.
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
        // Ensure resultContinuation is finished so newResultTask exits via the stream
        // (yielding StorageError.cancelled) rather than via Task cancellation
        // (which would throw CancellationError), keeping the error type deterministic.
        resultContinuation.finish()
      }
    )
  }
}

/// An event emitted during a transfer.
public enum TransferEvent<Success: Sendable>: Sendable {
  /// Periodic progress update during an active transfer.
  case progress(TransferProgress)
  /// The transfer finished successfully. Terminal — the stream ends after this event.
  case completed(Success)
  /// The transfer failed or was cancelled. Terminal — the stream ends after this event.
  case failed(StorageError)
}

/// Byte-level progress for a transfer.
public struct TransferProgress: Sendable {
  /// Number of bytes sent or received so far.
  public let bytesTransferred: Int64

  /// Total size of the transfer in bytes.
  public let totalBytes: Int64

  /// Transfer completion as a value between `0.0` and `1.0`.
  /// Returns `0` when `totalBytes` is zero.
  public var fractionCompleted: Double {
    guard totalBytes > 0 else { return 0 }
    return Double(bytesTransferred) / Double(totalBytes)
  }
}

/// A handle for an upload.
///
/// The success value is a ``FileUploadResponse`` containing the storage path and object ID.
/// TUS uploads support ``StorageTransferTask/pause()``, ``StorageTransferTask/resume()``, and
/// ``StorageTransferTask/cancel()``; multipart uploads only support cancel.
public typealias StorageUploadTask = StorageTransferTask<FileUploadResponse>

/// A handle for a download to disk.
///
/// The success value is a `URL` pointing to a temporary file on disk.
/// Move or read the file before the app exits — it is not guaranteed to persist across launches.
public typealias StorageDownloadTask = StorageTransferTask<URL>
