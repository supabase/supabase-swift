//
//  DownloadSessionDelegateTests.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import Foundation
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite struct DownloadSessionDelegateTests {

  @Test func routesProgressToCorrectTask() async throws {
    let delegate = DownloadSessionDelegate()
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

    let (stream1, continuation1, task1) = delegate.makeDownloadTask(
      in: session, request: URLRequest(url: URL(string: "https://example.com/file1")!))
    let (stream2, continuation2, task2) = delegate.makeDownloadTask(
      in: session, request: URLRequest(url: URL(string: "https://example.com/file2")!))

    // Simulate progress for task1 only
    delegate.urlSession(
      session, downloadTask: task1,
      didWriteData: 500, totalBytesWritten: 500, totalBytesExpectedToWrite: 1000
    )

    var task1Events: [TransferEvent<URL>] = []
    var task2Events: [TransferEvent<URL>] = []

    continuation2.finish()
    for await event in stream2 { task2Events.append(event) }

    continuation1.finish()
    for await event in stream1 { task1Events.append(event) }

    #expect(task1Events.count == 1)
    if case .progress(let p) = task1Events[0] {
      #expect(p.bytesTransferred == 500)
      #expect(p.totalBytes == 1000)
    } else {
      Issue.record("Expected .progress")
    }
    #expect(task2Events.isEmpty)
  }

  @Test func completionMovesFileAndYieldsURL() async throws {
    let delegate = DownloadSessionDelegate()
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

    let (stream, _, task) = delegate.makeDownloadTask(
      in: session, request: URLRequest(url: URL(string: "https://example.com/file")!))

    let tmpSrc = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try Data("content".utf8).write(to: tmpSrc)

    delegate.urlSession(session, downloadTask: task, didFinishDownloadingTo: tmpSrc)

    var completedURL: URL?
    for await event in stream {
      if case .completed(let url) = event { completedURL = url }
    }
    let url = try #require(completedURL)
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(!FileManager.default.fileExists(atPath: tmpSrc.path))
  }

  @Test func networkErrorYieldsFailedEvent() async {
    let delegate = DownloadSessionDelegate()
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

    let (stream, _, task) = delegate.makeDownloadTask(
      in: session, request: URLRequest(url: URL(string: "https://example.com/file")!))

    let error = URLError(.networkConnectionLost)
    delegate.urlSession(session, task: task, didCompleteWithError: error)

    var lastEvent: TransferEvent<URL>?
    for await event in stream { lastEvent = event }

    if case .failed(let storageError) = lastEvent {
      #expect(storageError.errorCode == .networkError)
    } else {
      Issue.record("Expected .failed(.networkError)")
    }
  }
}
