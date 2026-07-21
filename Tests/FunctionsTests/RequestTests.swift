//
//  RequestTests.swift
//
//
//  Created by Guilherme Souza on 23/04/24.
//

import Foundation
import SnapshotTesting
import Testing

@testable import Functions

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct RequestTests {
  let url = URL(string: "http://localhost:5432/functions/v1")!
  let apiKey = "supabase.publishable.key"

  @Test
  func invokeWithDefaultOptions() async {
    await snapshot {
      try await $0.invoke("hello-world")
    }
  }

  @Test
  func invokeWithCustomMethod() async {
    await snapshot {
      try await $0.invoke("hello-world", options: .init(method: .patch))
    }
  }

  @Test
  func invokeWithCustomRegion() async {
    await snapshot {
      try await $0.invoke("hello-world", options: .init(region: .apNortheast1))
    }
  }

  @Test
  func invokeWithCustomHeader() async {
    await snapshot {
      try await $0.invoke("hello-world", options: .init(headers: ["x-custom-key": "custom value"]))
    }
  }

  @Test
  func invokeWithBody() async {
    await snapshot {
      try await $0.invoke("hello-world", options: .init(body: ["name": "Supabase"]))
    }
  }

  func snapshot(
    record: SnapshotTestingConfiguration.Record? = nil,
    _ test: (FunctionsClient) async throws -> Void,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
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
        assertSnapshot(
          of: request,
          as: .curl,
          record: record,
          fileID: fileID,
          file: filePath,
          testName: testName,
          line: line,
          column: column
        )
      }
      throw NSError(domain: "Error", code: 0, userInfo: nil)
    }

    try? await test(sut)
  }
}
