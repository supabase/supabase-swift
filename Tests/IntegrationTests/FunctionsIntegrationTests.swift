//
//  FunctionsIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/01/25.
//

import Supabase
import XCTest

final class FunctionsIntegrationTests: XCTestCase {

  let sut = SupabaseClient(
    supabaseURL: URL(string: DotEnv.SUPABASE_URL)!,
    supabaseKey: DotEnv.SUPABASE_ANON_KEY
  )

  func testInvokeWithStreamedResponse() async throws {
    let response = sut.functions
      ._invokeWithStreamedResponse("stream")

    var chunks = [Data]()
    for try await chunk in response.prefix(3) {
      chunks.append(chunk)
    }

    XCTAssertEqual(
      chunks.map { String(decoding: $0, as: UTF8.self) },
      [
        "data: hello\r\n\r\n",
        "data: hello\r\n\r\n",
        "data: hello\r\n\r\n",
      ]
    )
  }
}
