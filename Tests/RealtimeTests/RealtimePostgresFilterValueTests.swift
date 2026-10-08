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
      RealtimePostgresFilter.format(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)
        == "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
  }

  @Test
  func date() {
    #expect(
      RealtimePostgresFilter.format(Date(timeIntervalSince1970: 1_737_465_985))
        == "2025-01-21T13:26:25.000Z"
    )
  }

  @Test
  func scalars() {
    #expect(RealtimePostgresFilter.format("a b") == "a b")
    #expect(RealtimePostgresFilter.format(42) == "42")
    #expect(RealtimePostgresFilter.format(1.5) == "1.5")
    #expect(RealtimePostgresFilter.format(true) == "true")
  }

  @Test
  func rawRepresentableUsesItsRawValue() {
    enum Status: String, RealtimePostgresFilterValue {
      case draft
    }
    #expect(RealtimePostgresFilter.format(Status.draft) == "draft")
  }
}
