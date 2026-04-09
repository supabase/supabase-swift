//
//  PostgrestURLLengthAndTimeoutTests.swift
//  Supabase
//

import Foundation
import Mocker
import XCTest

@testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class PostgrestURLLengthAndTimeoutTests: PostgrestQueryTests {

  final class MockLogger: SupabaseLogger, @unchecked Sendable {
    var warningLogs: [String] = []

    func log(message: SupabaseLogMessage) {
      if message.level == .warning {
        warningLogs.append(message.message)
      }
    }
  }

  func testURLLengthWarningIsLoggedWhenExceedingLimit() async throws {
    let logger = MockLogger()
    let client = PostgrestClient(
      url: url,
      logger: logger,
      fetch: { try await self.session.data(for: $0) },
      urlLengthLimit: 50
    )

    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .register()

    // URL will be something like: http://localhost:54321/rest/v1/users?select=id,username,email,created_at,updated_at
    // which is well over 50 characters
    try await client
      .from("users")
      .select("id,username,email,created_at,updated_at")
      .execute()

    XCTAssertFalse(logger.warningLogs.isEmpty, "Expected a warning log for URL exceeding limit")
    XCTAssertTrue(
      logger.warningLogs[0].contains("exceeds the limit of 50"),
      "Expected warning to mention the limit"
    )
  }

  func testNoURLLengthWarningWhenWithinLimit() async throws {
    let logger = MockLogger()
    let client = PostgrestClient(
      url: url,
      logger: logger,
      fetch: { try await self.session.data(for: $0) },
      urlLengthLimit: 8000
    )

    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .register()

    try await client
      .from("users")
      .select()
      .execute()

    XCTAssertTrue(logger.warningLogs.isEmpty, "Expected no warning log for short URL")
  }

  func testTimeoutIsAppliedToRequest() async throws {
    var capturedTimeoutInterval: TimeInterval?

    let client = PostgrestClient(
      url: url,
      fetch: { request in
        capturedTimeoutInterval = request.timeoutInterval
        return (
          Data("[]".utf8),
          HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
          )!
        )
      },
      timeout: 5.0
    )

    try await client
      .from("users")
      .select()
      .execute()

    XCTAssertEqual(capturedTimeoutInterval, 5.0)
  }

  func testDefaultTimeoutIntervalUsedWhenNoTimeoutConfigured() async throws {
    var capturedTimeoutInterval: TimeInterval?

    let client = PostgrestClient(
      url: url,
      fetch: { request in
        capturedTimeoutInterval = request.timeoutInterval
        return (
          Data("[]".utf8),
          HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
          )!
        )
      }
    )

    try await client
      .from("users")
      .select()
      .execute()

    // Default URLSession timeout is 60 seconds
    XCTAssertEqual(capturedTimeoutInterval, 60.0)
  }

  func testConfigurationStoresTimeoutAndURLLengthLimit() {
    let config = PostgrestClient.Configuration(
      url: url,
      timeout: 30.0,
      urlLengthLimit: 5000
    )
    XCTAssertEqual(config.timeout, 30.0)
    XCTAssertEqual(config.urlLengthLimit, 5000)
  }

  func testConfigurationDefaultsForTimeoutAndURLLengthLimit() {
    let config = PostgrestClient.Configuration(url: url)
    XCTAssertNil(config.timeout)
    XCTAssertEqual(config.urlLengthLimit, 8000)
  }
}
