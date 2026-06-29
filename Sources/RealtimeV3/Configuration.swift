//
//  Configuration.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import Foundation
import HTTPTypes
import Helpers

// MARK: - RealtimeProtocolVersion

/// The Phoenix channel protocol version used for the WebSocket connection.
public enum RealtimeProtocolVersion: String, Sendable {
  case v1 = "1.0.0"
  case v2 = "2.0.0"
}

// MARK: - Configuration

/// Configuration for the Realtime connection.
public struct Configuration: Sendable {
  /// Interval between heartbeat pings. Default: 25 seconds.
  public var heartbeat: Duration = .seconds(25)

  /// Maximum time to wait for a channel join acknowledgement. Default: 10 seconds.
  public var joinTimeout: Duration = .seconds(10)

  /// Maximum time to wait for a channel leave acknowledgement. Default: 10 seconds.
  public var leaveTimeout: Duration = .seconds(10)

  /// Maximum time to wait for a broadcast acknowledgement. Default: 5 seconds.
  public var broadcastAckTimeout: Duration = .seconds(5)

  /// Reconnection policy applied when the connection drops. Default: exponential backoff.
  public var reconnection: ReconnectionPolicy = .exponentialBackoff(
    initial: .seconds(1), max: .seconds(30), jitter: 0.2
  )

  /// How long to keep an idle socket open after the last channel has left,
  /// to avoid reconnect churn when a new channel joins shortly after.
  /// `.zero` means close immediately. Default: 50 seconds.
  public var disconnectOnEmptyChannelsAfter: Duration = .seconds(50)

  /// Whether the SDK manages connection lifecycle based on app lifecycle events.
  /// Default: `.automatic` on iOS/macOS/tvOS/visionOS, `.manual` on watchOS/Linux.
  public var lifecycle: LifecyclePolicy = .automaticDefault

  /// Phoenix protocol version used for the WebSocket connection. Default: `.v2`.
  public var protocolVersion: RealtimeProtocolVersion = .v2

  /// Clock used for timers and scheduling. Default: `ContinuousClock`.
  public var clock: any Clock<Duration> & Sendable = ContinuousClock()

  /// Additional HTTP headers sent with the WebSocket upgrade request.
  public var headers: HTTPFields = [:]

  // TODO(Task 31): add logger once RealtimeLogger is defined.
  // public var logger: (any RealtimeLogger)? = nil

  /// JSON decoder used to decode messages from the server. Default: ISO 8601 date strategy.
  public var decoder: JSONDecoder = .realtimeDefault

  /// JSON encoder used to encode messages to the server. Default: ISO 8601 date strategy.
  public var encoder: JSONEncoder = .realtimeDefault

  public init() {}

  /// Default configuration matching the specification.
  public static let `default` = Configuration()
}

// MARK: - JSONDecoder + realtimeDefault

extension JSONDecoder {
  /// SDK-provided decoder configured with ISO 8601 date strategy.
  /// Replace via `Configuration.decoder` for custom needs.
  public static let realtimeDefault: JSONDecoder = .supabase()
}

// MARK: - JSONEncoder + realtimeDefault

extension JSONEncoder {
  /// SDK-provided encoder configured with ISO 8601 date strategy.
  public static let realtimeDefault: JSONEncoder = .supabase()
}
