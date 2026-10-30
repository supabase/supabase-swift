//
//  RealtimeStatusMatching.swift
//  TestHelpers
//

package import Realtime

// The Realtime status enums are not `Equatable`: their cases carry errors. Tests that only care
// about the case compare against these, with `==`. Tests that check the values match the case.

/// A ``RealtimeClientStatus`` case without its values.
package enum ClientStatusCase: Sendable {
  case disconnected, connecting, connected, reconnecting
}

/// A ``RealtimeChannelStatus`` case without its values.
package enum ChannelStatusCase: Sendable {
  case unsubscribed, subscribing, subscribed, resubscribing, unsubscribing, failed
}

extension RealtimeClientStatus {
  package var statusCase: ClientStatusCase {
    switch self {
    case .disconnected: .disconnected
    case .connecting: .connecting
    case .connected: .connected
    case .reconnecting: .reconnecting
    }
  }
}

extension RealtimeChannelStatus {
  package var statusCase: ChannelStatusCase {
    switch self {
    case .unsubscribed: .unsubscribed
    case .subscribing: .subscribing
    case .subscribed: .subscribed
    case .resubscribing: .resubscribing
    case .unsubscribing: .unsubscribing
    case .failed: .failed
    }
  }
}

package func == (lhs: RealtimeClientStatus?, rhs: ClientStatusCase) -> Bool {
  lhs?.statusCase == rhs
}

package func != (lhs: RealtimeClientStatus?, rhs: ClientStatusCase) -> Bool {
  !(lhs == rhs)
}

package func == (lhs: [RealtimeClientStatus], rhs: [ClientStatusCase]) -> Bool {
  lhs.map(\.statusCase) == rhs
}

package func == (lhs: RealtimeChannelStatus?, rhs: ChannelStatusCase) -> Bool {
  lhs?.statusCase == rhs
}

package func != (lhs: RealtimeChannelStatus?, rhs: ChannelStatusCase) -> Bool {
  !(lhs == rhs)
}

package func == (lhs: [RealtimeChannelStatus], rhs: [ChannelStatusCase]) -> Bool {
  lhs.map(\.statusCase) == rhs
}

extension Sequence where Element == RealtimeClientStatus {
  package func contains(_ statusCase: ClientStatusCase) -> Bool {
    contains { $0.statusCase == statusCase }
  }
}

extension Sequence where Element == RealtimeChannelStatus {
  package func contains(_ statusCase: ChannelStatusCase) -> Bool {
    contains { $0.statusCase == statusCase }
  }
}
