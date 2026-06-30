//
//  SupabaseClientTransportTests.swift
//  HelpersTests
//

import Foundation
import Testing
@testable import Helpers

@Suite("SupabaseClientTransport")
struct SupabaseClientTransportTests {
  @Test("init does not crash")
  func initSucceeds() {
    let transport = SupabaseClientTransport()
    _ = transport  // Sendable — just verify it constructs
  }
}
