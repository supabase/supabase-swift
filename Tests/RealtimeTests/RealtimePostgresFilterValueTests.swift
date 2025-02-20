//
//  RealtimePostgresFilterValueTests.swift
//  Supabase
//
//  Created by Lucas Abijmil on 19/02/2025.
//

import XCTest
@testable import Realtime

final class RealtimePostgresFilterValueTests: XCTestCase {
  func testUUID() {
    XCTAssertEqual(
      UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!.rawValue,
      "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
  }

  func testDate() {
    XCTAssertEqual(
      Date(timeIntervalSince1970: 1_737_465_985).rawValue,
      "2025-01-21T13:26:25.000Z"
    )
  }
}
