//
//  RequestTests.swift
//
//
//  Created by Guilherme Souza on 23/04/24.
//

import SnapshotTesting
import XCTest

@testable import Functions

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class RequestTests: XCTestCase {
  let url = URL(string: "http://localhost:5432/functions/v1")!
  let apiKey = "supabase.anon.key"

  func testInvokeWithDefaultOptions() async {
    await snapshot {
      try await $0.invoke("hello-world")
    }
  }

  func testInvokeWithCustomMethod() async {
    await snapshot {
      try await $0.invoke("hello-world", options: .init(method: .patch))
    }
  }

  func testInvokeWithCustomRegion() async {
    await snapshot {
      try await $0.invoke("hello-world", options: .init(region: .apNortheast1))
    }
  }

  func testInvokeWithCustomHeader() async {
    await snapshot {
      try await $0.invoke(
        "hello-world",
        options: .init(headers: [.init("x-custom-key")!: "custom value"])
      )
    }
  }

  func testInvokeWithBody() async {
    await snapshot {
      try await $0.invoke("hello-world", options: .init(body: ["name": "Supabase"]))
    }
  }

  func snapshot(
    record: Bool = false,
    _ test: (FunctionsClient) async throws -> Void,
    file: StaticString = #file,
    testName: String = #function,
    line: UInt = #line
  ) async {
    let sut = FunctionsClient(
      url: url,
      headers: [.apiKey: apiKey, .xClientInfo: "functions-swift/x.y.z"]
    ) { request, bodyData in
      await MainActor.run {
        var request = URLRequest(httpRequest: request)!
        request.httpBody = bodyData
        assertSnapshot(
          of: request,
          as: .curl,
          record: record,
          file: file,
          testName: testName,
          line: line
        )
      }
      throw NSError(domain: "Error", code: 0, userInfo: nil)
    }

    try? await test(sut)
  }
}
