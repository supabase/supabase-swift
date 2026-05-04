//
//  TUSUploadEngineTests.swift
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

  @Test func postCreatesUploadWithCorrectHeaders() async throws {
    nonisolated(unsafe) var capturedRequest: URLRequest?

    var postMock = Mock(
      url: uploadURL,
      contentType: .json,
      statusCode: 201,
      data: [.post: Data()],
      additionalHeaders: ["Location": locationURL.absoluteString]
    )
    postMock.onRequestHandler = OnRequestHandler(requestCallback: { request in
      capturedRequest = request
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

    let request = try #require(capturedRequest)
    #expect(request.value(forHTTPHeaderField: "Tus-Resumable") == "1.0.0")
    #expect(request.value(forHTTPHeaderField: "Upload-Length") == "5")
    let metadata = try #require(request.value(forHTTPHeaderField: "Upload-Metadata"))
    #expect(metadata.contains("bucketName"))
    #expect(metadata.contains("objectName"))
    #expect(metadata.contains("contentType"))
  }
}
