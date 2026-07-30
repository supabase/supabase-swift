//
//  RealtimeErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/07/25.
//

import Foundation
import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct RealtimeErrorTests {
  @Test
  func realtimeErrorInitialization() {
    let errorMessage = "Connection failed"
    let error = RealtimeError(errorMessage)

    #expect(error.errorDescription == errorMessage)
  }

  @Test
  func realtimeErrorLocalizedDescription() {
    let errorMessage = "Test error message"
    let error = RealtimeError(errorMessage)

    // LocalizedError protocol provides localizedDescription
    #expect(error.localizedDescription == errorMessage)
  }

  @Test
  func realtimeErrorWithEmptyMessage() {
    let error = RealtimeError("")
    #expect(error.errorDescription == "")
  }

  @Test
  func realtimeErrorAsError() {
    let errorMessage = "Network timeout"
    let realtimeError = RealtimeError(errorMessage)
    let error: Error = realtimeError

    // Test that it can be used as a general Error
    #expect(error.localizedDescription == errorMessage)
  }

  @Test
  func realtimeErrorEquality() {
    let error1 = RealtimeError("Same message")
    let error2 = RealtimeError("Same message")
    let error3 = RealtimeError("Different message")

    // Since RealtimeError doesn't implement Equatable, we test the description
    #expect(error1.errorDescription == error2.errorDescription)
    #expect(error1.errorDescription != error3.errorDescription)
  }
}
