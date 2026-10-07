//
//  PostgrestCancellationIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/10/26.
//

import Foundation
import PostgREST
import Testing

/// The live half of `PostgrestCancellationTests`: cancelling the `Task` that awaits `execute()`
/// tears down a request that is genuinely in flight on `URLSession`, instead of waiting for the
/// server to finish. `sleep_for` is in `supabase/migrations/20261007000000_sleep_for.sql`.
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
    // Well under the 10 s the function sleeps for: the task did not wait for the server.
    #expect(ContinuousClock.now - start < .seconds(5))
  }
}
