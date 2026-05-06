//
//  DownloadEngine.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

actor DownloadEngine {
  enum State {
    case idle
    /// A download task has been enqueued but the `URLSessionDownloadTask` has not been created yet
    /// (e.g. waiting on the auth-token request to complete). Setting this state before scheduling
    /// the async work prevents duplicate starts from concurrent ``start()`` or ``resume()`` calls.
    case starting
    case downloading(URLSessionDownloadTask)
    /// The task was intentionally paused via ``pause()``.
    /// `resumeData` is nil when the server does not support range requests.
    case paused(resumeData: Data?)
    case completed(URL)
    case failed(StorageError)
    case cancelled

    var isTerminal: Bool {
      switch self {
      case .completed, .failed, .cancelled: return true
      default: return false
      }
    }
  }

  private let session: URLSession
  private let delegate: DownloadSessionDelegate
  private let requestBuilder: @Sendable () async throws -> URLRequest
  private let eventsContinuation: AsyncStream<TransferEvent<URL>>.Continuation
  private let resultContinuation: AsyncStream<Result<URL, any Error>>.Continuation

  private var state: State = .idle

  init(
    session: URLSession,
    delegate: DownloadSessionDelegate,
    requestBuilder: @Sendable @escaping () async throws -> URLRequest,
    eventsContinuation: AsyncStream<TransferEvent<URL>>.Continuation,
    resultContinuation: AsyncStream<Result<URL, any Error>>.Continuation
  ) {
    self.session = session
    self.delegate = delegate
    self.requestBuilder = requestBuilder
    self.eventsContinuation = eventsContinuation
    self.resultContinuation = resultContinuation
  }

  func start() async {
    guard case .idle = state else { return }
    state = .starting
    await startDownload(resumeData: nil)
  }

  /// Pauses an active download.
  ///
  /// Calls `URLSessionDownloadTask.cancel(byProducingResumeData:)` to capture any available
  /// resume data. If the server sent `Accept-Ranges: bytes` and an `ETag` or `Last-Modified`
  /// header, the data will be non-nil and ``resume()`` will restart the download from where
  /// it stopped. If resume data is unavailable the download restarts from byte 0 on ``resume()``.
  func pause() async {
    guard case .downloading(let task) = state else { return }
    state = .paused(resumeData: nil)
    // Await the resume-data callback so we capture whatever the server provides before
    // returning. The actor is suspended during this await; other calls (e.g. cancel()) can
    // run in the meantime — the `if case .paused` guard below handles that safely.
    let resumeData = await withCheckedContinuation { continuation in
      task.cancel(byProducingResumeData: { data in continuation.resume(returning: data) })
    }
    if case .paused = state {
      state = .paused(resumeData: resumeData)
    }
  }

  /// Resumes a paused download.
  ///
  /// If resume data was captured during ``pause()``, the session continues from the last
  /// received byte. Otherwise the entire download is restarted from the beginning.
  func resume() async {
    guard case .paused(let resumeData) = state else { return }
    state = .starting
    await startDownload(resumeData: resumeData)
  }

  /// Cancels the download immediately.
  func cancel() {
    guard !state.isTerminal else { return }
    if case .downloading(let task) = state {
      task.cancel()
    }
    state = .cancelled
    let error = StorageError.cancelled
    eventsContinuation.yield(.failed(error))
    eventsContinuation.finish()
    resultContinuation.yield(.failure(error))
    resultContinuation.finish()
  }

  // MARK: - Private

  private func startDownload(resumeData: Data?) async {
    guard case .starting = state else { return }

    do {
      let urlTask: URLSessionDownloadTask
      if let resumeData {
        urlTask = session.downloadTask(withResumeData: resumeData)
      } else {
        let request = try await requestBuilder()
        // Re-check: the task may have been cancelled while we awaited the request builder.
        guard case .starting = state else { return }
        urlTask = session.downloadTask(with: request)
      }

      delegate.register(
        taskIdentifier: urlTask.taskIdentifier,
        callbacks: DownloadTaskCallbacks(
          onProgress: { [weak self] totalBytesWritten, totalBytesExpectedToWrite in
            Task { [weak self] in
              await self?.didWriteData(
                totalBytesWritten: totalBytesWritten,
                totalBytesExpectedToWrite: totalBytesExpectedToWrite
              )
            }
          },
          onFinished: { [weak self] result in
            // The delegate has already moved the file synchronously.
            // Notify the engine of the result from a Task so we don't block the delegate queue.
            Task { [weak self] in await self?.didFinish(result) }
          },
          onCompleteWithError: { [weak self] error in
            Task { [weak self] in await self?.didCompleteWithError(error) }
          }
        )
      )

      state = .downloading(urlTask)
      urlTask.resume()
    } catch {
      guard !state.isTerminal else { return }
      finish(with: .failure(StorageError.from(error)))
    }
  }

  private func didWriteData(totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    guard case .downloading = state else { return }
    eventsContinuation.yield(
      .progress(
        TransferProgress(
          bytesTransferred: totalBytesWritten,
          totalBytes: totalBytesExpectedToWrite
        )))
  }

  /// Called after the delegate has moved the downloaded file to a stable temp location.
  ///
  /// The file move is performed synchronously by `DownloadSessionDelegate` inside
  /// `urlSession(_:downloadTask:didFinishDownloadingTo:)` — before URLSession reclaims the
  /// original temp file. This method just forwards the result to `finish(with:)`.
  private func didFinish(_ result: Result<URL, StorageError>) {
    guard !state.isTerminal else { return }
    finish(with: result.mapError { $0 as any Error })
  }

  private func didCompleteWithError(_ error: (any Error)?) {
    guard let error else { return }  // nil means success; handled by didFinishDownloading

    switch state {
    case .paused:
      // Intentional: pause() called cancel(byProducingResumeData:), which fires
      // didCompleteWithError with URLError.cancelled. Ignore it.
      return
    case .starting:
      // resume() set state to .starting for a new download; a stale URLError.cancelled
      // from the just-cancelled task must not propagate to the new one.
      return
    case .cancelled, .completed, .failed:
      // Already terminal — nothing to do.
      return
    case .downloading:
      if (error as? URLError)?.code == .cancelled {
        // External cancellation (e.g. system pressure, explicit cancel()) while actively
        // downloading. cancel() already sets state to .cancelled before this runs, so
        // reaching here means a third-party or system cancellation — shut down cleanly.
        cancel()
      } else {
        finish(with: .failure(StorageError.networkError(underlying: error)))
      }
    case .idle:
      return
    }
  }

  private func finish(with result: Result<URL, any Error>) {
    switch result {
    case .success(let url):
      state = .completed(url)
      eventsContinuation.yield(.completed(url))
    case .failure(let error):
      let storageError = error as? StorageError ?? StorageError.networkError(underlying: error)
      state = .failed(storageError)
      eventsContinuation.yield(.failed(storageError))
    }
    eventsContinuation.finish()
    resultContinuation.yield(result.mapError { $0 })
    resultContinuation.finish()
  }
}

// MARK: - Factory

extension DownloadEngine {
  static func makeTask(
    session: URLSession,
    delegate: DownloadSessionDelegate,
    requestBuilder: @Sendable @escaping () async throws -> URLRequest
  ) -> StorageDownloadTask {
    let (eventStream, eventsContinuation) =
      AsyncStream<TransferEvent<URL>>.makeStream()
    let (resultStream, resultContinuation) =
      AsyncStream<Result<URL, any Error>>.makeStream(bufferingPolicy: .bufferingNewest(1))

    let engine = DownloadEngine(
      session: session,
      delegate: delegate,
      requestBuilder: requestBuilder,
      eventsContinuation: eventsContinuation,
      resultContinuation: resultContinuation
    )

    eventsContinuation.onTermination = { reason in
      guard case .cancelled = reason else { return }
      Task { await engine.cancel() }
    }

    let resultTask = Task<URL, any Error> {
      for await r in resultStream { return try r.get() }
      throw StorageError.cancelled
    }

    let task = StorageDownloadTask(
      events: eventStream,
      resultTask: resultTask,
      pause: { await engine.pause() },
      resume: { await engine.resume() },
      cancel: { await engine.cancel() }
    )

    Task { await engine.start() }

    return task
  }
}
