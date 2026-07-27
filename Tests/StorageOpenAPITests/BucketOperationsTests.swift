//
//  BucketOperationsTests.swift
//  StorageOpenAPI
//
//  Created by Guilherme Souza on 08/07/26.
//

import Foundation
import HTTPRuntime
import Testing

@testable import StorageOpenAPI

/// A fake `HTTPTransport` that answers every request from a caller-supplied
/// closure. Shared by the StorageOpenAPI test suite so no test ever touches
/// the network.
struct FakeTransport: HTTPTransport {
  var onSend: @Sendable (HTTPRequest) throws -> HTTPResponse

  func send(_ request: HTTPRequest, uploadProgress: ProgressHandler?) async throws(HTTPError)
    -> HTTPResponse
  {
    do {
      return try onSend(request)
    } catch {
      throw HTTPError.transport(error)
    }
  }

  func stream(_ request: HTTPRequest) async throws(HTTPError) -> HTTPResponseStream {
    let response: HTTPResponse
    do {
      response = try onSend(request)
    } catch {
      throw HTTPError.transport(error)
    }
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
      return HTTPResponse(head: HTTPResponseHead(status: 200, headers: [:]), body: responseBody)
    }
    let client = StorageOpenAPIClient(
      baseURL: URL(string: "https://example.supabase.co/storage/v1")!, transport: transport)

    let bucket = try await client.bucketGet(bucketId: "avatars")

    #expect(bucket.id == "avatars")
    #expect(bucket.public == true)
  }
}
