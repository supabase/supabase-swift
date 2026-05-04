//
//  DownloadSessionDelegate.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// Full implementation added in Task 7.
final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  func setBackgroundCompletionHandler(_ handler: @escaping @Sendable () -> Void) {}

  func makeStorageDownloadTask(in session: URLSession, request: URLRequest) -> StorageDownloadTask {
    fatalError("DownloadSessionDelegate not yet implemented — complete Task 7")
  }

  // MARK: URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    // Stub — full implementation in Task 7.
  }
}
