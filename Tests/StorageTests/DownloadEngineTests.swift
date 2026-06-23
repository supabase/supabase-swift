//
//  DownloadEngineTests.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

// Darwin-only for the same reason as StorageDownloadTaskTests: swift-corelibs-foundation
// crashes when a custom URLProtocol intercepts a URLSessionDownloadTask on Linux.
// SequentialMockProtocol calls urlProtocolDidFinishLoading, which triggers the same forced
// cast that traps in _ProtocolClient.urlProtocolDidFinishLoading on Linux.
#if canImport(Darwin)

  import Foundation
  import Testing

  @testable import Storage

  @Suite(.serialized) struct DownloadEngineTests {

    static let baseURL = URL(string: "http://localhost:54321/storage/v1")!
    static let bucketId = "test-bucket"

    let client: StorageClient
    let bucket: StorageFileAPI

    init() {
      SequentialMockProtocol.reset()
      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [SequentialMockProtocol.self]
      let session = URLSession(configuration: config)
      client = StorageClient(
        url: Self.baseURL,
        configuration: StorageClientConfiguration(
          headers: ["Authorization": "Bearer test-token"],
          session: session,
          logger: nil
        )
      )
      bucket = client.from(Self.bucketId)
    }

    // MARK: - Basic download

    @Test func downloadCompletesSuccessfully() async throws {
      let fileContents = Data("hello download".utf8)
      SequentialMockProtocol.responses = [
        (200, ["Content-Length": "\(fileContents.count)"], fileContents)
      ]

      let url = try await bucket.download(path: "images/photo.png").value

      #expect(FileManager.default.fileExists(atPath: url.path))
      let receivedData = try Data(contentsOf: url)
      #expect(receivedData == fileContents)
      try? FileManager.default.removeItem(at: url)
    }

    @Test func networkErrorYieldsFailedEvent() async throws {
      // No responses → SequentialMockProtocol returns URLError.badServerResponse
      SequentialMockProtocol.responses = []
      SequentialMockProtocol.hangWhenExhausted = false

      let task = bucket.download(path: "images/missing.png")

      var lastEvent: TransferEvent<URL>?
      for await event in task.events { lastEvent = event }

      guard case .failed = lastEvent else {
        Issue.record("Expected .failed event, got \(String(describing: lastEvent))")
        return
      }
    }

    // MARK: - Pause / resume

    /// Verifies that pausing a hanging download and then resuming it (from scratch, since no
    /// real bytes were transferred and thus no resume data) eventually completes the download.
    @Test func pauseAndResumeCompletesDownload() async throws {
      // First request hangs — simulates a slow download we want to pause.
      SequentialMockProtocol.hangWhenExhausted = true
      SequentialMockProtocol.responses = []

      let task = bucket.download(path: "images/photo.png")

      // Wait for the download task to enter the hanging request.
      var hangIter = SequentialMockProtocol.nextHang.makeAsyncIterator()
      _ = await hangIter.next()

      // Pause — cancels the hanging URLSessionDownloadTask.
      await task.pause()

      // Wait for stopLoading() to be called so we know the cancel reached the protocol.
      var cancelIter = SequentialMockProtocol.hangCancelled.makeAsyncIterator()
      _ = await cancelIter.next()

      // Provide a response for the resumed download.
      // Resume data will be nil (no bytes were actually written), so resume() restarts
      // from byte 0.
      let fileContents = Data("resumed content".utf8)
      SequentialMockProtocol.hangWhenExhausted = false
      SequentialMockProtocol.appendResponse(
        (200, ["Content-Length": "\(fileContents.count)"], fileContents))

      await task.resume()

      let url = try await task.value
      #expect(FileManager.default.fileExists(atPath: url.path))
      let receivedData = try Data(contentsOf: url)
      #expect(receivedData == fileContents)
      try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Cancel

    @Test func cancelYieldsCancelledError() async throws {
      SequentialMockProtocol.hangWhenExhausted = true
      SequentialMockProtocol.responses = []

      let task = bucket.download(path: "images/photo.png")

      var hangIter = SequentialMockProtocol.nextHang.makeAsyncIterator()
      _ = await hangIter.next()

      await task.cancel()

      var lastEvent: TransferEvent<URL>?
      for await event in task.events { lastEvent = event }

      guard case .failed(let error) = lastEvent else {
        Issue.record("Expected .failed event, got \(String(describing: lastEvent))")
        return
      }
      #expect(error.errorCode == .cancelled)
    }

    @Test func cancelThrowsFromValue() async throws {
      SequentialMockProtocol.hangWhenExhausted = true
      SequentialMockProtocol.responses = []

      let task = bucket.download(path: "images/photo.png")

      var hangIter = SequentialMockProtocol.nextHang.makeAsyncIterator()
      _ = await hangIter.next()

      await task.cancel()

      do {
        _ = try await task.value
        Issue.record("Expected an error to be thrown")
      } catch let error as StorageError {
        #expect(error.errorCode == .cancelled)
      }
    }
  }

#endif  // canImport(Darwin)
