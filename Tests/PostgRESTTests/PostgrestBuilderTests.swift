//
//  PostgrestBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/08/24.
//

import InlineSnapshotTesting
import Mocker
import XCTest

@testable import PostgREST

final class PostgrestBuilderTests: PostgrestQueryTests {
  func testCustomHeaderOnAPerCallBasis() throws {
    let url = URL(string: "http://localhost:54321/rest/v1")!
    let postgrest1 = PostgrestClient(url: url, headers: ["apikey": "foo"], logger: nil)
    let postgrest2 = try postgrest1.rpc("void_func").setHeader(name: .init("apikey")!, value: "bar")

    // Original client object isn't affected
    XCTAssertEqual(
      postgrest1.from("users").select().mutableState.request.headers[.init("apikey")!], "foo")
    // Derived client object uses new header value
    XCTAssertEqual(postgrest2.mutableState.request.headers[.init("apikey")!], "bar")
  }

  func testExecuteWithNonSuccessStatusCode() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 400,
      data: [
        .get: Data(
          """
          {
            "message": "Bad Request"
          }
          """.utf8
        )
      ]
    )
    .register()

    do {
      try await sut
        .from("users")
        .select()
        .execute()
    } catch let error as PostgrestError {
      XCTAssertEqual(error.message, "Bad Request")
    }
  }

  func testExecuteWithNonJSONError() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 400,
      data: [
        .get: Data("Bad Request".utf8)
      ]
    )
    .register()

    do {
      try await sut
        .from("users")
        .select()
        .execute()
    } catch let error as HTTPError {
      XCTAssertEqual(error.data, Data("Bad Request".utf8))
      XCTAssertEqual(error.response.statusCode, 400)
    }
  }
}
