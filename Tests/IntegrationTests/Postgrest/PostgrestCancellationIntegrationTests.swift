//
//  PostgrestCancellationIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/10/26.
//

import Foundation
import PostgREST
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestCancellationIntegrationTests {
  let client = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["apikey": DotEnv.supabasePublishableKey]
  )

  @Test
  func cancellingTheTaskAbandonsAnInFlightRequest() async throws {
    let start = ContinuousClock.now
    let task = Task {
      try await client.rpc("sleep_for", params: ["seconds": 10]).execute()
    }
    try await Task.sleep(for: .milliseconds(300))
    task.cancel()

    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(ContinuousClock.now - start < .seconds(5))
  }
}
