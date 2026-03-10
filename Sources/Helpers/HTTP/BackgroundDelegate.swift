//
//  BackgroundDelegate.swift
//
//
//  Created by Claude Code on 26/02/26.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if !os(Linux) && !os(Windows) && !os(Android)

  /// URLSessionDelegate for handling background upload/download tasks.
  ///
  /// This delegate manages background transfer lifecycle, including progress updates,
  /// completion handling, and reconnection to background sessions after app relaunch.
  package final class BackgroundDelegate: NSObject, URLSessionDownloadDelegate,
    URLSessionTaskDelegate, @unchecked Sendable
  {
    private let lock = NSLock()
    private var progressContinuation:
      AsyncStream<(bytesTransferred: Int64, totalBytes: Int64)>.Continuation?
    private var completionHandler: (@Sendable (HTTPResponse) -> Void)?
    private var errorHandler: (@Sendable (any Error) -> Void)?

    package override init() {
      super.init()
    }

    package func setHandlers(
      progressContinuation: AsyncStream<(bytesTransferred: Int64, totalBytes: Int64)>.Continuation?,
      completionHandler: @escaping @Sendable (HTTPResponse) -> Void,
      errorHandler: @escaping @Sendable (any Error) -> Void
    ) {
      _ = lock.withLock {
        self.progressContinuation = progressContinuation
        self.completionHandler = completionHandler
        self.errorHandler = errorHandler
      }
    }

    // MARK: - URLSessionDownloadDelegate

    package func urlSession(
      _ session: URLSession,
      downloadTask: URLSessionDownloadTask,
      didWriteData bytesWritten: Int64,
      totalBytesWritten: Int64,
      totalBytesExpectedToWrite: Int64
    ) {
      // Report download progress
      _ = lock.withLock {
        progressContinuation?.yield((totalBytesWritten, totalBytesExpectedToWrite))
      }
    }

    package func urlSession(
      _ session: URLSession,
      downloadTask: URLSessionDownloadTask,
      didFinishDownloadingTo location: URL
    ) {
      do {
        // Read the downloaded data
        let data = try Data(contentsOf: location)

        guard let httpResponse = downloadTask.response as? HTTPURLResponse else {
          let error = URLError(.badServerResponse)
          lock.withLock {
            errorHandler?(error)
            progressContinuation?.finish()
          }
          return
        }

        let response = HTTPResponse(data: data, response: httpResponse)

        lock.withLock {
          completionHandler?(response)
          progressContinuation?.finish()
        }

        // Clean up temporary file
        try? FileManager.default.removeItem(at: location)
      } catch {
        lock.withLock {
          errorHandler?(error)
          progressContinuation?.finish()
        }
      }
    }

    // MARK: - URLSessionTaskDelegate

    package func urlSession(
      _ session: URLSession,
      task: URLSessionTask,
      didSendBodyData bytesSent: Int64,
      totalBytesSent: Int64,
      totalBytesExpectedToSend: Int64
    ) {
      // Report upload progress
      _ = lock.withLock {
        progressContinuation?.yield((totalBytesSent, totalBytesExpectedToSend))
      }
    }

    package func urlSession(
      _ session: URLSession,
      task: URLSessionTask,
      didCompleteWithError error: (any Error)?
    ) {
      if let error = error {
        lock.withLock {
          errorHandler?(error)
          progressContinuation?.finish()
        }
      }
      // For downloads, completion is handled in didFinishDownloadingTo
      // For uploads, we need to handle completion here if there's no download
      if task is URLSessionUploadTask, error == nil {
        if let httpResponse = task.response as? HTTPURLResponse {
          let response = HTTPResponse(data: Data(), response: httpResponse)
          lock.withLock {
            completionHandler?(response)
            progressContinuation?.finish()
          }
        }
      }
    }
  }

#endif
