//
//  RealtimePostgresFilterValueTests.swift
//  Supabase
//
//  Created by Lucas Abijmil on 19/02/2025.
//

import Foundation
import Testing

@testable import Realtime

@Suite
struct RealtimePostgresFilterValueTests {
  @Test
  func uuid() {
    #expect(
      UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!.realtimeFilterValue
        == "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
  }

  @Test
  func date() {
    #expect(
      Date(timeIntervalSince1970: 1_737_465_985).realtimeFilterValue
        == "2025-01-21T13:26:25.000Z"
    )
  }

  @Test
  func scalars() {
    #expect("a b".realtimeFilterValue == "a b")
    #expect(42.realtimeFilterValue == "42")
    #expect(1.5.realtimeFilterValue == "1.5")
    #expect(true.realtimeFilterValue == "true")
  }

  @Test
  func customValueUsesItsRequirement() {
    struct Status: RealtimePostgresFilterValue {
      var realtimeFilterValue: String { "draft" }
    }
    #expect(RealtimePostgresFilter.eq("status", value: Status()).value == "status=eq.draft")
  }
}
