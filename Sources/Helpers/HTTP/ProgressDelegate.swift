//
//  ProgressDelegate.swift
//
//
//  Created by Claude Code on 26/02/26.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// URLSessionDelegate for handling upload/download progress.
///
/// This delegate tracks bytes transferred and reports progress via a callback.
/// It accumulates received data for downloads and handles completion.
package final class ProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate,
  @unchecked Sendable
{
  private let progressHandler: @Sendable (Int64, Int64) -> Void
  private let completion: CheckedContinuation<(Data, URLResponse), any Error>
  private let lock = NSLock()
  private var receivedData = Data()
  private var response: URLResponse?

  package init(
    progressHandler: @escaping @Sendable (Int64, Int64) -> Void,
    completion: CheckedContinuation<(Data, URLResponse), any Error>
  ) {
    self.progressHandler = progressHandler
    self.completion = completion
    super.init()
  }

  // MARK: - URLSessionTaskDelegate (Upload Progress)

  package func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    // Report upload progress
    progressHandler(totalBytesSent, totalBytesExpectedToSend)
  }

  // MARK: - URLSessionDataDelegate (Download Progress)

  package func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    lock.withLock {
      self.response = response
    }
    completionHandler(.allow)
  }

  package func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    lock.withLock {
      receivedData.append(data)
    }

    // Report download progress
    let expectedLength = dataTask.response?.expectedContentLength ?? -1
    let receivedLength = Int64(receivedData.count)
    progressHandler(receivedLength, expectedLength)
  }

  // MARK: - URLSessionTaskDelegate (Completion)

  package func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    if let error = error {
      completion.resume(throwing: error)
    } else if let response = lock.withLock({ self.response }) {
      let data = lock.withLock { receivedData }
      completion.resume(returning: (data, response))
    } else {
      completion.resume(throwing: URLError(.badServerResponse))
    }
  }
}
