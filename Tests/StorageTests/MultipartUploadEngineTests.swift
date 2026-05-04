//
//  MultipartUploadEngineTests.swift
//  StorageTests
//

import ConcurrencyExtras
import Foundation
import Mocker
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite struct MultipartUploadEngineStateTests {
  let dummyResponse = FileUploadResponse(
    id: UUID(), path: "f.txt", fullPath: "bucket/f.txt")
  let dummyError = StorageError(message: "oops", errorCode: .unknown)

  @Test func nonTerminalStatesReturnFalse() {
    #expect(!MultipartUploadEngine.State.idle.isTerminal)
    #expect(!MultipartUploadEngine.State.uploading.isTerminal)
  }

  @Test func terminalStatesReturnTrue() {
    #expect(MultipartUploadEngine.State.completed(dummyResponse).isTerminal)
    #expect(MultipartUploadEngine.State.failed(dummyError).isTerminal)
    #expect(MultipartUploadEngine.State.cancelled.isTerminal)
  }
}

@Suite(.serialized) struct MultipartUploadEngineTests {

  let baseURL = URL(string: "http://localhost:54321/storage/v1")!

  var client: StorageClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockingURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return StorageClient(
      url: baseURL,
      configuration: StorageClientConfiguration(
        headers: ["Authorization": "Bearer test-token"],
        session: session
      )
    )
  }

  @Test func uploadDataCompletesAndReturnsResponse() async throws {
    let objectURL = baseURL.appendingPathComponent("object/bucket/file.txt")
    let responseJSON = """
      {"Key":"bucket/file.txt","Id":"EAA8BDB5-2E00-4767-B5A9-D2502EFE2196"}
      """
    Mock(
      url: objectURL,
      contentType: .json,
      statusCode: 200,
      data: [.post: Data(responseJSON.utf8)]
    ).register()

    let task = MultipartUploadEngine.makeTask(
      bucketId: "bucket",
      path: "file.txt",
      source: .data(Data("hello world".utf8)),
      options: FileOptions(),
      client: client
    )

    let response = try await task.value
    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
    #expect(response.id == UUID(uuidString: "EAA8BDB5-2E00-4767-B5A9-D2502EFE2196"))
  }

  @Test func uploadSetsUpsertHeader() async throws {
    let objectURL = baseURL.appendingPathComponent("object/bucket/file.txt")
    let responseJSON = """
      {"Key":"bucket/file.txt","Id":"EAA8BDB5-2E00-4767-B5A9-D2502EFE2196"}
      """

    let capturedRequest = LockIsolated<URLRequest?>(nil)
    var mock = Mock(
      url: objectURL,
      contentType: .json,
      statusCode: 200,
      data: [.post: Data(responseJSON.utf8)]
    )
    mock.onRequestHandler = OnRequestHandler(requestCallback: { capturedRequest.setValue($0) })
    mock.register()

    let options = FileOptions(upsert: true)
    let task = MultipartUploadEngine.makeTask(
      bucketId: "bucket",
      path: "file.txt",
      source: .data(Data("hello".utf8)),
      options: options,
      client: client
    )
    _ = try await task.value

    let req = try #require(capturedRequest.value)
    #expect(req.value(forHTTPHeaderField: "x-upsert") == "true")
  }

  @Test func uploadSetsMultipartContentType() async throws {
    let objectURL = baseURL.appendingPathComponent("object/bucket/photo.jpg")
    let responseJSON = """
      {"Key":"bucket/photo.jpg","Id":"EAA8BDB5-2E00-4767-B5A9-D2502EFE2196"}
      """

    let capturedRequest = LockIsolated<URLRequest?>(nil)
    var mock = Mock(
      url: objectURL,
      contentType: .json,
      statusCode: 200,
      data: [.post: Data(responseJSON.utf8)]
    )
    mock.onRequestHandler = OnRequestHandler(requestCallback: { capturedRequest.setValue($0) })
    mock.register()

    let task = MultipartUploadEngine.makeTask(
      bucketId: "bucket",
      path: "photo.jpg",
      source: .data(Data("imagedata".utf8)),
      options: FileOptions(),
      client: client
    )
    _ = try await task.value

    let req = try #require(capturedRequest.value)
    let contentType = try #require(req.value(forHTTPHeaderField: "Content-Type"))
    #expect(contentType.hasPrefix("multipart/form-data; boundary="))
  }

  @Test func cancelFinishesWithCancelledError() async {
    // No mock registered — cancel immediately before network call completes.
    let task = MultipartUploadEngine.makeTask(
      bucketId: "bucket",
      path: "file.txt",
      source: .data(Data("hello".utf8)),
      options: FileOptions(),
      client: client
    )
    await task.cancel()

    do {
      _ = try await task.value
      Issue.record("Expected cancellation error")
    } catch let error as StorageError {
      #expect(error.errorCode == .cancelled)
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }
}
