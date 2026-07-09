//
//  BucketOperationsTests.swift
//  StorageOpenAPI
//
//  Created by Guilherme Souza on 08/07/26.
//

import Foundation
import HTTPRuntime
import Testing

@testable import Storage

/// A fake `HTTPTransport` that answers every request from a caller-supplied
/// closure. Shared by the StorageOpenAPI test suite so no test ever touches
/// the network.
///
/// `HTTPRequest`/`HTTPResponse` are qualified with the `HTTPRuntime` module
/// name here because `@testable import Storage` also re-exports `Helpers`
/// (see `Sources/Storage/Exports.swift`), which declares its own same-named
/// package types — an ambiguity that only surfaces when both modules are
/// imported side by side, as in this file.
struct FakeTransport: HTTPRuntime.HTTPTransport {
  var onSend: @Sendable (HTTPRuntime.HTTPRequest) throws -> HTTPRuntime.HTTPResponse

  func send(_ request: HTTPRuntime.HTTPRequest, uploadProgress: ProgressHandler?) async throws
    -> HTTPRuntime.HTTPResponse
  {
    try onSend(request)
  }

  func stream(_ request: HTTPRuntime.HTTPRequest) async throws -> HTTPResponseStream {
    let response = try onSend(request)
    return HTTPResponseStream(
      head: response.head,
      body: AsyncThrowingStream { continuation in
        continuation.yield(response.body)
        continuation.finish()
      }
    )
  }
}

@Suite
struct BucketOperationsTests {

  @Test
  func bucketGetDecodesASuccessResponse() async throws {
    let responseBody = Data(#"{"id":"avatars","name":"avatars","public":true}"#.utf8)
    let transport = FakeTransport { request in
      #expect(request.url.path.hasSuffix("/bucket/avatars"))
      return HTTPRuntime.HTTPResponse(
        head: HTTPResponseHead(status: 200, headers: [:]), body: responseBody)
    }
    let client = StorageOpenAPIClient(
      baseURL: URL(string: "https://example.supabase.co/storage/v1")!, transport: transport)

    let bucket = try await client.bucketGet(bucketId: "avatars")

    #expect(bucket.id == "avatars")
    #expect(bucket.public == true)
  }
}
