//
//  StorageDownloadTaskTests.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import Foundation
import Mocker
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// Tests for the public download() and downloadData() APIs on StorageFileAPI.
// They verify the full wiring: StorageFileAPI → DownloadSessionDelegate → StorageDownloadTask.
// The download session's protocolClasses are propagated from the HTTP session (see StorageClient.init),
// so MockingURLProtocol intercepts both HTTP and download tasks.
@Suite(.serialized)
struct StorageDownloadTaskTests {

  static let baseURL = URL(string: "http://localhost:54321/storage/v1")!
  static let bucketId = "test-bucket"

  let client: StorageClient
  let bucket: StorageFileAPI

  init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockingURLProtocol.self]
    let session = URLSession(configuration: configuration)
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

  // MARK: - download()

  @Test func downloadDeliversFileOnDisk() async throws {
    let fileContents = Data("hello download".utf8)
    let path = "images/photo.png"
    let downloadURL = Self.baseURL
      .appendingPathComponent("object/authenticated/\(Self.bucketId)/\(path)")
    Mock(url: downloadURL, statusCode: 200, data: [.get: fileContents]).register()

    let url = try await bucket.download(path: path).value

    #expect(FileManager.default.fileExists(atPath: url.path))
    let receivedData = try Data(contentsOf: url)
    #expect(receivedData == fileContents)
    try? FileManager.default.removeItem(at: url)
  }

  @Test func downloadYieldsCompletedEventWithValidURL() async throws {
    let path = "docs/report.pdf"
    let downloadURL = Self.baseURL
      .appendingPathComponent("object/authenticated/\(Self.bucketId)/\(path)")
    Mock(url: downloadURL, statusCode: 200, data: [.get: Data("pdf content".utf8)]).register()

    let task = bucket.download(path: path)
    var completedURL: URL?
    for await event in task.events {
      if case .completed(let url) = event { completedURL = url }
    }

    let url = try #require(completedURL)
    #expect(FileManager.default.fileExists(atPath: url.path))
    try? FileManager.default.removeItem(at: url)
  }

  @Test func downloadNetworkFailureYieldsFailedEvent() async throws {
    let path = "missing/file.txt"
    let downloadURL = Self.baseURL
      .appendingPathComponent("object/authenticated/\(Self.bucketId)/\(path)")
    Mock(
      url: downloadURL,
      statusCode: 200,
      data: [.get: Data()],
      requestError: URLError(.networkConnectionLost)
    ).register()

    let task = bucket.download(path: path)
    var lastEvent: TransferEvent<URL>?
    for await event in task.events { lastEvent = event }

    guard case .failed(let error) = lastEvent else {
      Issue.record("Expected .failed event, got \(String(describing: lastEvent))")
      return
    }
    #expect(error.errorCode == .networkError)
  }

  @Test func downloadNetworkFailureThrowsFromValue() async throws {
    let path = "missing/file2.txt"
    let downloadURL = Self.baseURL
      .appendingPathComponent("object/authenticated/\(Self.bucketId)/\(path)")
    Mock(
      url: downloadURL,
      statusCode: 200,
      data: [.get: Data()],
      requestError: URLError(.networkConnectionLost)
    ).register()

    do {
      _ = try await bucket.download(path: path).value
      Issue.record("Expected an error to be thrown")
    } catch let error as StorageError {
      #expect(error.errorCode == .networkError)
    }
  }

  // MARK: - downloadData()

  @Test func downloadDataReturnsFileContents() async throws {
    let fileContents = Data("file data contents".utf8)
    let path = "text/readme.txt"
    let downloadURL = Self.baseURL
      .appendingPathComponent("object/authenticated/\(Self.bucketId)/\(path)")
    Mock(url: downloadURL, statusCode: 200, data: [.get: fileContents]).register()

    let data = try await bucket.downloadData(path: path).value

    #expect(data == fileContents)
  }

}
