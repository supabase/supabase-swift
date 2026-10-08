//
//  WithTimeoutTests.swift
//
//
//  Created by Guilherme Souza on 19/04/24.
//

import Helpers
import Testing

@Suite
struct WithTimeoutTests {
  @Test
  func throwsTimeoutErrorWhenOperationOutlivesDuration() async {
    await #expect(throws: TimeoutError.self) {
      try await withTimeout(.milliseconds(50)) {
        try await Task.sleep(for: .seconds(10))
      }
    }
  }

  @Test
  func returnsResultWhenOperationFinishesInTime() async throws {
    let answer = try await withTimeout(.seconds(10)) { 42 }
    #expect(answer == 42)
  }
}
