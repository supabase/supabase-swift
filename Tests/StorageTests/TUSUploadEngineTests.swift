//
//  TUSUploadEngineTests.swift
//  Storage
//
//  Created by Guilherme Souza on 04/05/26.
//

import ConcurrencyExtras
import Foundation
import Mocker
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized) struct TUSUploadEngineTests {

  let baseURL = URL(string: "https://example.supabase.co/storage/v1")!
  let uploadURL = URL(string: "https://example.supabase.co/storage/v1/upload/resumable")!
  let locationURL = URL(
    string: "https://example.supabase.co/storage/v1/upload/resumable/test-id")!

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

  // MARK: - Helpers

  private func makeTUSServerResponseData(path: String, fullPath: String) throws -> Data {
    // TUSUploadServerResponse shape: {"Key": "<fullPath>", "Id": "<uuid>"}
    let json = "{\"Key\":\"\(fullPath)\",\"Id\":\"E621E1F8-C36C-495A-93FC-0C247A3E6E5F\"}"
    return Data(json.utf8)
  }

  // MARK: - Tests

  @Test func postCreatesUploadWithCorrectHeaders() async throws {
    let capturedRequest = LockIsolated<URLRequest?>(nil)

    var postMock = Mock(
      url: uploadURL,
      contentType: .json,
      statusCode: 201,
      data: [.post: Data()],
      additionalHeaders: ["Location": locationURL.absoluteString]
    )
    postMock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      capturedRequest.setValue(request)
    })
    postMock.register()

    // Register a PATCH mock so the engine can proceed past POST without error
    let patchResponseJSON = """
      {"Key":"bucket/test.txt","Id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"}
      """
    Mock(
      url: locationURL,
      contentType: .json,
      statusCode: 200,
      data: [.patch: Data(patchResponseJSON.utf8)],
      additionalHeaders: ["Upload-Offset": "5"]
    ).register()

    let data = Data("hello".utf8)
    let task = TUSUploadEngine.makeTask(
      bucketId: "bucket",
      path: "test.txt",
      source: .data(data),
      options: FileOptions(contentType: "text/plain", upsert: false),
      client: client
    )
    _ = try await task.result

    let request = try #require(capturedRequest.value)
    #expect(request.value(forHTTPHeaderField: "Tus-Resumable") == "1.0.0")
    #expect(request.value(forHTTPHeaderField: "Upload-Length") == "5")
    let metadata = try #require(request.value(forHTTPHeaderField: "Upload-Metadata"))
    #expect(metadata.contains("bucketName"))
    #expect(metadata.contains("objectName"))
    #expect(metadata.contains("contentType"))
    #expect(metadata.contains("cacheControl"))
  }

  @Test func sendsTwoChunksForDataLargerThanChunkSize() async throws {
    // 7 MB data → 2 chunks (6 MB + 1 MB)
    let data = Data(repeating: 0x42, count: 7 * 1024 * 1024)
    let patchCount = LockIsolated(0)
    let patchOffsets = LockIsolated<[Int64]>([])

    // POST mock
    Mock(
      url: uploadURL,
      contentType: .json,
      statusCode: 201,
      data: [.post: Data()],
      additionalHeaders: ["Location": locationURL.absoluteString]
    ).register()

    // Second PATCH mock (offset 6MB → 7MB, returns final response)
    let finalResponse = try makeTUSServerResponseData(path: "big.bin", fullPath: "bucket/big.bin")
    var patch2 = Mock(
      url: locationURL,
      contentType: .json,
      statusCode: 200,
      data: [.patch: finalResponse],
      additionalHeaders: ["Upload-Offset": "\(7 * 1024 * 1024)"]
    )
    patch2.onRequestHandler = OnRequestHandler(requestCallback: { request in
      patchCount.withValue { $0 += 1 }
      if let offsetStr = request.value(forHTTPHeaderField: "Upload-Offset"),
        let offset = Int64(offsetStr)
      {
        patchOffsets.withValue { $0.append(offset) }
      }
    })

    // First PATCH mock (offset 0 → 6MB, returns 204)
    // Uses completion callback to swap in patch2 after it fires
    var patch1 = Mock(
      url: locationURL,
      contentType: .json,
      statusCode: 204,
      data: [.patch: Data()],
      additionalHeaders: ["Upload-Offset": "\(6 * 1024 * 1024)"]
    )
    patch1.onRequestHandler = OnRequestHandler(requestCallback: { request in
      patchCount.withValue { $0 += 1 }
      if let offsetStr = request.value(forHTTPHeaderField: "Upload-Offset"),
        let offset = Int64(offsetStr)
      {
        patchOffsets.withValue { $0.append(offset) }
      }
    })
    patch1.completion = {
      patch2.register()
    }
    patch1.register()

    let task = TUSUploadEngine.makeTask(
      bucketId: "bucket",
      path: "big.bin",
      source: .data(data),
      options: FileOptions(contentType: "application/octet-stream"),
      client: client
    )
    _ = try await task.result

    #expect(patchCount.value == 2)
    #expect(patchOffsets.value == [0, Int64(6 * 1024 * 1024)])
  }

  @Test func emitsProgressEventsPerChunk() async throws {
    let data = Data(repeating: 0x01, count: 7 * 1024 * 1024)

    // POST mock
    Mock(
      url: uploadURL,
      contentType: .json,
      statusCode: 201,
      data: [.post: Data()],
      additionalHeaders: ["Location": locationURL.absoluteString]
    ).register()

    let finalResponse = try makeTUSServerResponseData(path: "f.bin", fullPath: "bucket/f.bin")

    // Second PATCH mock
    var patch2 = Mock(
      url: locationURL,
      contentType: .json,
      statusCode: 200,
      data: [.patch: finalResponse],
      additionalHeaders: ["Upload-Offset": "\(7 * 1024 * 1024)"]
    )

    // First PATCH mock — swaps in patch2 on completion
    var patch1 = Mock(
      url: locationURL,
      contentType: .json,
      statusCode: 204,
      data: [.patch: Data()],
      additionalHeaders: ["Upload-Offset": "\(6 * 1024 * 1024)"]
    )
    patch1.completion = {
      patch2.register()
    }
    patch1.register()

    let task = TUSUploadEngine.makeTask(
      bucketId: "bucket",
      path: "f.bin",
      source: .data(data),
      options: FileOptions(contentType: "application/octet-stream"),
      client: client
    )

    var progressFractions: [Double] = []
    for await event in task.events {
      if case .progress(let p) = event {
        progressFractions.append(p.fractionCompleted)
      }
    }

    #expect(progressFractions.count == 2)
    #expect(progressFractions[0] < progressFractions[1])
    #expect(progressFractions[1] == 1.0)
  }

  @Test func resyncesOffsetOn409() async throws {
    let data = Data(repeating: 0x01, count: 100)
    let headCount = LockIsolated(0)

    // POST mock
    Mock(
      url: uploadURL,
      contentType: .json,
      statusCode: 201,
      data: [.post: Data()],
      additionalHeaders: ["Location": locationURL.absoluteString]
    ).register()

    let finalResponse = try makeTUSServerResponseData(path: "x.txt", fullPath: "bucket/x.txt")

    // Second PATCH (retry from offset 0 after re-sync) → success
    var patch2 = Mock(
      url: locationURL,
      contentType: .json,
      statusCode: 200,
      data: [.patch: finalResponse],
      additionalHeaders: ["Upload-Offset": "100"]
    )

    // HEAD for re-sync — swaps in patch2 on completion
    var headMock = Mock(
      url: locationURL,
      contentType: .json,
      statusCode: 200,
      data: [.head: Data()],
      additionalHeaders: ["Upload-Offset": "0"]
    )
    headMock.onRequestHandler = OnRequestHandler(requestCallback: { _ in
      headCount.withValue { $0 += 1 }
    })
    headMock.completion = {
      patch2.register()
    }
    headMock.register()

    // First PATCH → 409 (triggers HEAD re-sync)
    Mock(
      url: locationURL,
      contentType: .json,
      statusCode: 409,
      data: [.patch: Data()]
    ).register()

    let task = TUSUploadEngine.makeTask(
      bucketId: "bucket",
      path: "x.txt",
      source: .data(data),
      options: FileOptions(contentType: "text/plain"),
      client: client
    )
    _ = try await task.result

    #expect(headCount.value == 1)
  }
}
