//
//  Types.swift
//
//
//  Created by Guilherme Souza on 13/05/24.
//

import Alamofire
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Options for initializing ``RealtimeClient``.
public struct RealtimeClientOptions: Sendable {
  package var headers: HTTPHeaders
  var heartbeatInterval: TimeInterval
  var reconnectDelay: TimeInterval
  public var timeoutInterval: TimeInterval
  var disconnectOnSessionLoss: Bool
  var connectOnSubscribe: Bool
  var maxRetryAttempts: Int

  /// Sets the log level for Realtime
  var logLevel: LogLevel?
  public var session: Alamofire.Session?
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
    session: Alamofire.Session? = nil,
    accessToken: (@Sendable () async throws -> String?)? = nil,
    logger: (any SupabaseLogger)? = nil
  ) {
    self.headers = HTTPHeaders(headers)
    self.heartbeatInterval = heartbeatInterval
    self.reconnectDelay = reconnectDelay
    self.timeoutInterval = timeoutInterval
    self.disconnectOnSessionLoss = disconnectOnSessionLoss
    self.connectOnSubscribe = connectOnSubscribe
    self.maxRetryAttempts = maxRetryAttempts
    self.logLevel = logLevel
    self.session = session
    self.accessToken = accessToken
    self.logger = logger
  }

  var apikey: String? {
    headers["apikey"]
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

/// Log level for Realtime.
public enum LogLevel: String, Sendable {
  case info, warn, error
}

/// Channel event constants.
public enum ChannelEvent {
  public static let system = "system"
  public static let postgresChanges = "postgres_changes"
  public static let broadcast = "broadcast"
  public static let close = "close"
  public static let error = "error"
  public static let presenceDiff = "presence_diff"
  public static let presenceState = "presence_state"
  public static let reply = "reply"
  public static let join = "phx_join"
  public static let leave = "phx_leave"
  public static let accessToken = "access_token"
  public static let presence = "presence"
}
