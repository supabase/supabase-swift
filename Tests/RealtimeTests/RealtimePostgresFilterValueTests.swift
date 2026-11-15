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
    #expect(Date(timeIntervalSince1970: 0).realtimeFilterValue == "1970-01-01T00:00:00.000Z")
  }

  @Test
  func stdlibValuesUseRealtimeFilterValue() {
    #expect(42.realtimeFilterValue == "42")
    #expect(1.5.realtimeFilterValue == "1.5")
    #expect(true.realtimeFilterValue == "true")
    #expect("a".realtimeFilterValue == "a")
  }

  @Test
  func filterIsSendable() {
    let filter: any Sendable = RealtimePostgresFilter.eq("id", value: 1)
    #expect(filter is RealtimePostgresFilter)
  }
}
