//
//  ObjectUploadTests.swift
//  StorageOpenAPI
//
//  Created by Guilherme Souza on 08/07/26.
//

import Foundation
import HTTPRuntime
import Testing

@testable import StorageOpenAPI

@Suite
struct ObjectUploadTests {

  // NOTE: the real Storage OpenAPI spec's `object#createObject` operation
  // declares a `multipart/form-data` (or raw binary) request body, but
  // Task 13's generator does not yet wire request bodies for `multipart`
  // content types into `StorageOpenAPIClient.objectUpload` — the generated
  // method takes only `bucketName`/`wildcard` and never calls `setBody`, so
  // no file content is ever sent. This test documents that real, current
  // behavior rather than asserting a multipart body that doesn't exist yet.
  @Test
  func objectUploadSendsNoBodyYet() async throws {
    let transport = FakeTransport { request in
      #expect(request.url.path.hasSuffix("/object/avatars/a.txt"))
      guard case .none = request.body else {
        Issue.record(
          "expected no request body to be set (multipart body generation is not yet implemented)")
        return HTTPResponse(head: HTTPResponseHead(status: 500, headers: [:]), body: Data())
      }
      let responseBody = Data(#"{"Key":"avatars/a.txt"}"#.utf8)
      return HTTPResponse(head: HTTPResponseHead(status: 200, headers: [:]), body: responseBody)
    }
    let client = StorageOpenAPIClient(
      baseURL: URL(string: "https://example.supabase.co/storage/v1")!, transport: transport)

    let result = try await client.objectUpload(bucketName: "avatars", wildcard: "a.txt")

    #expect(result.Key == "avatars/a.txt")
  }
}
