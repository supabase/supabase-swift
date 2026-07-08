//
//  ErrorDecodingTests.swift
//  StorageOpenAPI
//
//  Created by Guilherme Souza on 08/07/26.
//

import Foundation
import HTTPRuntime
import Testing

@testable import StorageOpenAPI

@Suite
struct ErrorDecodingTests {

  // The real generated `bucketGet` only registers status 403 -> ErrorSchema
  // (per the spec's documented error bindings for this operation); other
  // non-success statuses fall through to `HTTPError.unexpectedStatus`.
  @Test
  func bucketGetThrowsATypedErrorOn403() async throws {
    let errorBody = Data(
      #"{"message":"Access denied","error":"Forbidden","statusCode":"403"}"#.utf8)
    let transport = FakeTransport { _ in
      HTTPResponse(head: HTTPResponseHead(status: 403, headers: [:]), body: errorBody)
    }
    let client = StorageOpenAPIClient(
      baseURL: URL(string: "https://example.supabase.co/storage/v1")!, transport: transport)

    await #expect(throws: ErrorSchema.self) {
      _ = try await client.bucketGet(bucketId: "missing")
    }
  }

  @Test
  func bucketGetThrowsUnexpectedStatusOnUnmappedError() async throws {
    let transport = FakeTransport { _ in
      HTTPResponse(head: HTTPResponseHead(status: 404, headers: [:]), body: Data())
    }
    let client = StorageOpenAPIClient(
      baseURL: URL(string: "https://example.supabase.co/storage/v1")!, transport: transport)

    await #expect(throws: HTTPError.self) {
      _ = try await client.bucketGet(bucketId: "missing")
    }
  }
}
