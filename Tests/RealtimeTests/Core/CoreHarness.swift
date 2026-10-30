//
//  CoreHarness.swift
//  RealtimeTests
//

import Foundation
import Helpers
import Logging

@testable import Realtime

/// Drives a ``RealtimeCore`` by hand: events go in one at a time, at a time the test controls.
struct CoreHarness {
  var core: RealtimeCore
  var time: CoreTime
  /// The socket ``connected(options:)`` opened, or `nil` for a harness that never connected.
  var socket: FakeWebSocket?
  private var lastWaiter: UInt64 = 0

  init(
    options: RealtimeCore.Options = .test, initialToken: String? = nil, logger: Logger = .silent
  ) {
    core = RealtimeCore(options: options, logger: logger, initialToken: initialToken)
    time = CoreTime(elapsed: .zero, date: Date(timeIntervalSince1970: 0))
  }

  /// A harness whose core is `.connected` to ``socket``. Opening it made no refs and used no
  /// waiter ids.
  static func connected(
    options: RealtimeCore.Options = .test, initialToken: String? = nil, logger: Logger = .silent
  ) -> CoreHarness {
    var harness = CoreHarness(options: options, initialToken: initialToken, logger: logger)
    let socket = FakeWebSocket.fakes().0
    harness.socket = socket
    _ = harness.send(.connect(waiter: nil))
    _ = harness.send(.socketOpened(socket))
    return harness
  }

  mutating func send(_ event: RealtimeCore.Event) -> [RealtimeCore.Effect] {
    core.handle(event, at: time)
  }

  mutating func advance(by duration: Duration) {
    time.elapsed += duration
    time.date += duration.timeInterval
  }

  /// A fresh waiter id: 1, 2, 3…
  mutating func waiter() -> WaiterID {
    lastWaiter += 1
    return WaiterID(rawValue: lastWaiter)
  }
}

extension RealtimeCore.Options {
  /// A 10 s timeout, a 25 s heartbeat, no token provider, and backoffs that wait `attempt`
  /// seconds, so every row shows which attempt picked the delay.
  ///
  /// Computed: the backoff closures are not `Sendable`, so a stored static cannot hold them.
  static var test: Self {
    Self(
      timeout: .seconds(10),
      heartbeatInterval: .seconds(25),
      connectOnSubscribe: true,
      disconnectOnEmptyChannelsAfter: .seconds(50),
      hasAccessTokenProvider: false,
      accessTokenRefreshInterval: .seconds(10),
      accessTokenRefreshLeeway: .seconds(60),
      retryDelay: { .seconds($0) },
      rejoinDelay: { .seconds($0) }
    )
  }
}

extension Logger {
  /// A logger that drops everything, so test output stays clean.
  static let silent = Logger(label: "RealtimeCoreTests") { _ in SwiftLogNoOpLogHandler() }
}
