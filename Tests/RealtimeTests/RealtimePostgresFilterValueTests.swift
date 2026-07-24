//
//  RealtimePostgresFilterValueTests.swift
//  Supabase
//
//  Created by Lucas Abijmil on 19/02/2025.
//

import Foundation
import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct RealtimePostgresFilterValueTests {
  @Test
  func uuid() {
    #expect(
      UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!.rawValue
        == "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
  }

  @Test
  func date() {
    #expect(
      Date(timeIntervalSince1970: 1_737_465_985).rawValue
        == "2025-01-21T13:26:25.000Z"
    )
  }
}
