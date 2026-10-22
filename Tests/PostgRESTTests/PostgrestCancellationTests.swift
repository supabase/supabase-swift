//
//  PostgrestCancellationTests.swift
//  PostgREST
//
//  Created by Guilherme Souza on 07/10/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@_spi(Experimental) @testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct PostgrestCancellationTests {
  struct Todo: _PostgrestRelation {
    static let relationName = "todos"
    static let selectString = "*"
    var id: Int
    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
    }
    static let columns = Columns()
  }

  private final class HangingTransport: Sendable {
    let started = LockIsolated(false)
    let sawCancellation = LockIsolated(false)

    var transport: ClosureTransport {
      ClosureTransport { [started, sawCancellation] _, _ in
        started.setValue(true)
        while !Task.isCancelled { await Task.yield() }
        sawCancellation.setValue(true)
        throw URLError(.cancelled)
      }
    }
  }

  private func makeClient(
    transport: ClosureTransport,
    retryEnabled: Bool = false,
    clock: any Clock<Duration> = ContinuousClock()
  ) -> PostgrestClient {
    PostgrestClient(
      configuration: .init(
        url: URL(string: "http://localhost:54321/rest/v1")!,
        http: .init(transport: transport),
        retryEnabled: retryEnabled),
      clock: clock)
  }

  @Test
  func cancellingATypedQueryTearsDownTheExchange() async {
    let hanging = HangingTransport()
    let client = makeClient(transport: hanging.transport)

    let task = Task {
      try await client.from(Todo.self).select().execute()
    }
    await waitUntil { hanging.started.value }
    task.cancel()

    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(hanging.sawCancellation.value)
  }

  @Test
  func cancellingAnUntypedQueryTearsDownTheExchange() async {
    let hanging = HangingTransport()
    let client = makeClient(transport: hanging.transport)

    let task = Task {
      try await client.from("todos").select().execute()
    }
    await waitUntil { hanging.started.value }
    task.cancel()

    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(hanging.sawCancellation.value)
  }

  private struct SleepUntilCancelledClock: Clock {
    let inner = ContinuousClock()
    let sleeping = LockIsolated(false)
    var now: ContinuousClock.Instant { inner.now }
    var minimumResolution: Duration { inner.minimumResolution }

    func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
      sleeping.setValue(true)
      while !Task.isCancelled { await Task.yield() }
      throw CancellationError()
    }
  }

  @Test
  func cancellingDuringRetryBackoffStopsRetrying() async {
    let attempts = LockIsolated(0)
    let clock = SleepUntilCancelledClock()
    let client = makeClient(
      transport: ClosureTransport { _, _ in
        attempts.withValue { $0 += 1 }
        return (HTTPTypes.HTTPResponse(status: .serviceUnavailable), nil)
      },
      retryEnabled: true,
      clock: clock)

    let task = Task {
      try await client.from(Todo.self).select().execute()
    }
    await waitUntil { clock.sleeping.value }
    task.cancel()

    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(attempts.value == 1)
  }
}
