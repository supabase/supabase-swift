//
//  RealtimeBenchmarkTests.swift
//
//
//  Created by Guilherme Souza on 23/10/26.
//

#if !os(Android) && !os(Linux)
  import Foundation
  import Realtime
  import Testing

  @Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["REALTIME_BENCHMARK"] != nil)
  )
  struct RealtimeBenchmarkTests {
    @Test(.timeLimit(.minutes(3)))
    func selfBroadcastRoundTrip() async throws {
      let runs = Int(ProcessInfo.processInfo.environment["REALTIME_BENCHMARK_RUNS"] ?? "") ?? 1_000
      // The local stack allows 100 events per second per tenant; a faster loop gets dropped.
      let gap = Duration.milliseconds(
        Int(ProcessInfo.processInfo.environment["REALTIME_BENCHMARK_GAP_MS"] ?? "") ?? 25)
      let client = RealtimeClient(
        url: URL(string: DotEnv.supabaseURL)!.appendingPathComponent("realtime/v1"),
        options: RealtimeClientOptions(headers: ["apikey": DotEnv.supabasePublishableKey]))
      let channel = client.channel("rt2-bench-\(UUID().uuidString)") {
        $0.broadcast.receiveOwnBroadcasts = true
      }
      let echoes = channel.broadcastStream(event: "bench")
      try await channel.subscribeWithError()

      var iterator = echoes.makeAsyncIterator()
      var samples: [Duration] = []
      let clock = ContinuousClock()
      for run in 0..<(runs + 20) {
        let start = clock.now
        try await channel.broadcast(event: "bench", message: ["run": .integer(run)])
        _ = await iterator.next()
        if run >= 20 { samples.append(clock.now - start) }
        try await Task.sleep(for: gap)
      }

      let sorted = samples.sorted()
      let p50 = sorted[sorted.count / 2]
      let p95 = sorted[Int(Double(sorted.count) * 0.95)]
      print(
        "RealtimeBenchmark runs=\(sorted.count) p50_ms=\(milliseconds(p50)) p95_ms=\(milliseconds(p95))"
      )
      await client.removeAllChannels()
    }

    private func milliseconds(_ duration: Duration) -> String {
      let (seconds, attoseconds) = duration.components
      return String(format: "%.3f", Double(seconds) * 1_000 + Double(attoseconds) / 1e15)
    }
  }
#endif
