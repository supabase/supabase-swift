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

/// `database.using_modifiers.request_cancellation` is satisfied by Swift structured concurrency:
/// cancel the `Task` that awaits `execute()`. There is no `abortSignal` equivalent to register, so
/// these tests are what the compliance entry rests on. Each one cancels from outside and checks
/// three things: the exchange is torn down (the transport sees the cancellation), nothing is
/// retried, and the caller gets `CancellationError`, not a `PostgrestError` wrapping
/// `URLError(.cancelled)`.
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

  /// A transport that behaves like `URLSession` under cancellation: it stays in flight until the
  /// task is cancelled, then fails the exchange with `URLError(.cancelled)`.
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

  /// A clock whose sleep lasts until the task is cancelled, so the retry back-off is where the
  /// cancellation lands.
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
