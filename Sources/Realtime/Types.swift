//
//  Types.swift
//
//
//  Created by Guilherme Souza on 13/05/24.
//

import Foundation
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Options for initializing ``RealtimeClientV2``.
public struct RealtimeClientOptions: Sendable {
  package var headers: HTTPFields
  var heartbeatInterval: TimeInterval
  var reconnectDelay: TimeInterval
  var timeoutInterval: TimeInterval
  var disconnectOnSessionLoss: Bool
  var connectOnSubscribe: Bool
  var maxRetryAttempts: Int

  /// Sets the log level for Realtime
  var logLevel: LogLevel?
  var fetch: (@Sendable (_ request: URLRequest) async throws -> (Data, URLResponse))?
  package var accessToken: (@Sendable () async throws -> String?)?
  package var logger: (any SupabaseLogger)?

  public static let defaultHeartbeatInterval: TimeInterval = 25
  public static let defaultReconnectDelay: TimeInterval = 7
  public static let defaultTimeoutInterval: TimeInterval = 10
  public static let defaultDisconnectOnSessionLoss = true
  public static let defaultConnectOnSubscribe: Bool = true
  public static let defaultMaxRetryAttempts: Int = 5

  public init(
    headers: [String: String] = [:],
    heartbeatInterval: TimeInterval = Self.defaultHeartbeatInterval,
    reconnectDelay: TimeInterval = Self.defaultReconnectDelay,
    timeoutInterval: TimeInterval = Self.defaultTimeoutInterval,
    disconnectOnSessionLoss: Bool = Self.defaultDisconnectOnSessionLoss,
    connectOnSubscribe: Bool = Self.defaultConnectOnSubscribe,
    maxRetryAttempts: Int = Self.defaultMaxRetryAttempts,
    logLevel: LogLevel? = nil,
    fetch: (@Sendable (_ request: URLRequest) async throws -> (Data, URLResponse))? = nil,
    accessToken: (@Sendable () async throws -> String?)? = nil,
    logger: (any SupabaseLogger)? = nil
  ) {
    self.headers = HTTPFields(headers)
    self.heartbeatInterval = heartbeatInterval
    self.reconnectDelay = reconnectDelay
    self.timeoutInterval = timeoutInterval
    self.disconnectOnSessionLoss = disconnectOnSessionLoss
    self.connectOnSubscribe = connectOnSubscribe
    self.maxRetryAttempts = maxRetryAttempts
    self.logLevel = logLevel
    self.fetch = fetch
    self.accessToken = accessToken
    self.logger = logger
  }

  var apikey: String? {
    headers[.apiKey]
  }
}

public typealias RealtimeSubscription = ObservationToken

public enum RealtimeChannelStatus: Sendable {
  case unsubscribed
  case subscribing
  case subscribed
  case unsubscribing
}

public enum RealtimeClientStatus: Sendable, CustomStringConvertible {
  case disconnected
  case connecting
  case connected

  public var description: String {
    switch self {
    case .disconnected: "Disconnected"
    case .connecting: "Connecting"
    case .connected: "Connected"
    }
  }
}

public enum HeartbeatStatus: Sendable {
  /// Heartbeat was sent.
  case sent
  /// Heartbeat was received.
  case ok
  /// Server responded with an error.
  case error
  /// Heartbeat wasn't received in time.
  case timeout
  /// Socket is disconnected.
  case disconnected
}

extension HTTPField.Name {
  static let apiKey = Self("apiKey")!
}

/// Log level for Realtime.
public enum LogLevel: String, Sendable {
  case info, warn, error
}

struct BroadcastMessagePayload: Encodable {
  let messages: [Message]

  struct Message: Encodable {
    let topic: String
    let event: String
    let payload: JSONObject
    let `private`: Bool
  }
}

/// Represents the different events that can be sent through
/// a channel regarding a Channel's lifecycle.
enum ChannelEvent {
  static let join = "phx_join"
  static let leave = "phx_leave"
  static let close = "phx_close"
  static let error = "phx_error"
  static let reply = "phx_reply"
  static let system = "system"
  static let broadcast = "broadcast"
  static let accessToken = "access_token"
  static let presence = "presence"
  static let presenceDiff = "presence_diff"
  static let presenceState = "presence_state"
  static let postgresChanges = "postgres_changes"

  static let heartbeat = "heartbeat"

  static func isLifecyleEvent(_ event: String) -> Bool {
    switch event {
    case join, leave, reply, error, close: true
    default: false
    }
  }
}
