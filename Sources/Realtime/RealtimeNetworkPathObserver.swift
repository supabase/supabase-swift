//
//  RealtimeNetworkPathObserver.swift
//  Realtime
//

import ConcurrencyExtras
import Foundation

#if canImport(Network)
  import Network

  /// Watches the network path and hands the Realtime client a wake hint whenever the path is
  /// satisfied after the first report.
  ///
  /// The hint only cuts a reconnect backoff short; the client never waits for it. Apple documents
  /// that the path can stay unsatisfied on watchOS for ordinary apps (TN3135), so a report of no
  /// network is ignored and never stops the client from trying.
  ///
  /// The client owns the observer, so it is not `Sendable`. The monitor reports on its own serial
  /// queue and only yields ``Input/wake`` into the client's inbox. The observer cancels the
  /// monitor in its own `deinit`.
  final class RealtimeNetworkPathObserver {
    private let monitor = NWPathMonitor()

    init(inbox: AsyncStream<Input>.Continuation) {
      let hint = NetworkPathWakeHint(inbox: inbox)
      monitor.pathUpdateHandler = { path in hint.report(path.status) }
      monitor.start(queue: DispatchQueue(label: "io.supabase.realtime.network-path"))
    }

    deinit {
      monitor.cancel()
    }
  }

  /// Turns the statuses a path monitor reports into ``Input/wake`` inputs.
  ///
  /// The monitor reports the current path as soon as it starts. That report is a baseline, not a
  /// change, so it never wakes the client. Every later satisfied report does; the core ignores the
  /// hint unless a backoff wait is running. `.requiresConnection` is not satisfied: it says a
  /// connection attempt may bring a path up.
  final class NetworkPathWakeHint: Sendable {
    private let inbox: AsyncStream<Input>.Continuation
    private let hasReported = LockIsolated(false)

    init(inbox: AsyncStream<Input>.Continuation) {
      self.inbox = inbox
    }

    func report(_ status: NWPath.Status) {
      let isBaseline = hasReported.withValue { hasReported in
        defer { hasReported = true }
        return !hasReported
      }
      if !isBaseline, status == .satisfied {
        inbox.yield(.wake)
      }
    }
  }

#endif
