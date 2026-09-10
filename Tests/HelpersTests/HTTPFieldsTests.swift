//
//  HTTPFieldsTests.swift
//  Helpers
//
//  Created by Guilherme Souza on 09/09/26.
//

import Foundation
import HTTPTypes
import IssueReporting
import Testing

@testable import Helpers

/// Some keys reaching `HTTPFields.init(_:)` are dynamic — `HTTPResponse.init` builds fields from
/// `response.allHeaderFields`, which the server controls — so an invalid field name must not trap.
@Suite
struct HTTPFieldsTests {
  @Test
  func keepsValidFieldNames() {
    let fields = HTTPFields(["X-Client-Info": "swift/1", "Authorization": "Bearer token"])

    #expect(fields[.init("X-Client-Info")!] == "swift/1")
    #expect(fields[.authorization] == "Bearer token")
    #expect(fields.count == 2)
  }

  // The drop path reports. Under `swift test`, `withIssueReporters([])` keeps that report from
  // being recorded as a failure; under `xcodebuild test` nothing does, because `reportIssue` from
  // a `@Test` function segfaults the process there (SDK-435). CI runs `swift test` too, so gate
  // on the runner rather than dropping the coverage.
  @Test(
    .enabled(if: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil),
    arguments: ["", "Bad Header", "Bad:Header", "Bad\nHeader"]
  )
  func dropsAnInvalidFieldNameAndKeepsTheRest(invalidKey: String) {
    let fields = withIssueReporters([]) {
      HTTPFields([invalidKey: "dropped", "X-Client-Info": "swift/1"])
    }

    #expect(fields.count == 1)
    #expect(fields[.init("X-Client-Info")!] == "swift/1")
  }
}
