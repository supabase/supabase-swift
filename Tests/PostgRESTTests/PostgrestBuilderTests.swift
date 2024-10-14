//
//  PostgrestBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/08/24.
//

@testable import PostgREST
import XCTest

final class PostgrestBuilderTests: XCTestCase {
  let url = URL(string: "http://localhost:54321/rest/v1")!

  func testCustomHeaderOnAPerCallBasis() throws {
    let postgrest1 = PostgrestClient(url: url, headers: ["apikey": "foo"], logger: nil)
    let postgrest2 = try postgrest1.rpc("void_func").setHeader(name: .init("apikey")!, value: "bar")

    // Original client object isn't affected
    XCTAssertEqual(postgrest1.from("users").select().mutableState.request.headers[.init("apikey")!], "foo")
    // Derived client object uses new header value
    XCTAssertEqual(postgrest2.mutableState.request.headers[.init("apikey")!], "bar")
  }
}
