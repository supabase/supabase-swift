//
//  RequestTests.swift
//
//
//  Created by Guilherme Souza on 23/04/24.
//

@testable import Functions
import SnapshotTesting
import XCTest

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
      try await $0.invoke("hello-world", options: .init(headers: ["x-custom-key": "custom value"]))
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
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
  ) async {
    let sut = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey, "x-client-info": "functions-swift/x.y.z"]
    ) { request in
      await MainActor.run {
        #if os(Android)
        // missing snapshots for Android
        return
        #endif
        assertSnapshot(of: request, as: .curl, record: record, file: file, testName: testName, line: line)
      }
      throw NSError(domain: "Error", code: 0, userInfo: nil)
    }

    try? await test(sut)
  }
}
