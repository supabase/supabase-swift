//
//  ResponseWrapperFixtureTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/11/26.
//

import Foundation
import HTTPTypes
import Supabase
import Testing

/// Builds every response wrapper through its public memberwise init, the way an app builds a
/// fixture or a preview. A plain `import Supabase` keeps this file on the public surface, and
/// each assignment checks that the field is a `var`.
@Suite
struct ResponseWrapperFixtureTests {
  let headers: HTTPFields = [.sbRequestID: "req-1"]

  @Test
  func postgrestResponse() {
    var response = PostgrestResponse(
      status: .ok, headers: headers, body: Data("[]".utf8), count: 3, value: [Int]())
    response.value = [1]

    #expect(response.count == 3)
    #expect(response.requestID == "req-1")
    #expect(PostgrestResponse(status: .ok, headers: [:], body: Data(), value: ()).count == nil)
  }

  @Test
  func functionResponse() throws {
    var response = FunctionResponse(status: .ok, headers: headers, body: Data(#"{"a":1}"#.utf8))
    response.status = .created

    #expect(try response.decode(as: [String: Int].self) == ["a": 1])
  }

  @Test
  func functionStreamResponse() {
    var response = FunctionStreamResponse(status: .ok, headers: headers, body: HTTPBody(Data()))
    response.status = .created

    #expect(response.requestID == "req-1")
  }

  @Test
  func downloadResponse() async throws {
    var response = DownloadResponse(
      status: .partialContent, headers: headers, body: HTTPBody(Data("bytes".utf8)))
    response.headers[.eTag] = "\"abc\""

    #expect(response.eTag == "\"abc\"")
    #expect(response.requestID == "req-1")
    #expect(try await response.data() == Data("bytes".utf8))
  }

  @Test
  func httpErrorResponse() {
    var response = HTTPErrorResponse(status: 404, headers: headers, body: Data())
    response.status = .notFound

    #expect(response.requestID == "req-1")
  }
}
