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

/// Phoenix protocol version used for WebSocket communication.
public enum RealtimeProtocolVersion: String, Sendable {
  /// Protocol 1.0.0 — JSON object text frames for all messages.
  case v1 = "1.0.0"

  /// Protocol 2.0.0 — JSON array text frames for non-broadcast messages,
  /// binary frames for broadcast messages.
  case v2 = "2.0.0"
}

/// Options for initializing ``RealtimeClientV2``.
public struct RealtimeClientOptions: Sendable {
  package var headers: HTTPFields
  var heartbeatInterval: TimeInterval
  var reconnectDelay: TimeInterval
  var timeoutInterval: TimeInterval
  var disconnectOnSessionLoss: Bool
  var connectOnSubscribe: Bool
  var maxRetryAttempts: Int
  var disconnectOnEmptyChannelsAfter: TimeInterval

  /// The Phoenix serializer protocol version.
  public var vsn: RealtimeProtocolVersion

  /// Whether to automatically handle app lifecycle changes (background/foreground).
  ///
  /// When enabled, the client observes platform lifecycle notifications and — on
  /// foregrounding — reconnects and re-joins any existing channels if the WebSocket
  /// was closed while the app was backgrounded. The client does not proactively
  /// disconnect on backgrounding; short background/foreground cycles keep the
  /// connection alive without churn.
  ///
  /// Disable this to manage the connection yourself with ``RealtimeClientV2/connect()`` and
  /// ``RealtimeClientV2/disconnect(code:reason:)``.
  ///
  /// Default: `true` on iOS, macOS, tvOS, and visionOS. `false` on other platforms
  /// (including watchOS and Linux), where lifecycle observation is not supported.
  public var handleAppLifecycle: Bool

  /// Sets the log level for Realtime
  var logLevel: LogLevel?
  package var fetch: (@Sendable (_ request: URLRequest) async throws -> (Data, URLResponse))?
  package var accessToken: (@Sendable () async throws -> String?)?
  package var logger: (any SupabaseLogger)?

  public static let defaultHeartbeatInterval: TimeInterval = 25
  public static let defaultReconnectDelay: TimeInterval = 7
  public static let defaultTimeoutInterval: TimeInterval = 10
  public static let defaultDisconnectOnSessionLoss = true
  public static let defaultConnectOnSubscribe: Bool = true
  public static let defaultMaxRetryAttempts: Int = 5
  /// Defers the WebSocket disconnect after the last channel is removed, giving a window to reuse
  /// the existing connection when switching channels without a reconnect penalty. Defaults to
  /// `2 × defaultHeartbeatInterval`. Set to 0 for immediate disconnect. If a new channel is
  /// created before the timer fires, the pending disconnect is cancelled.
  public static let defaultDisconnectOnEmptyChannelsAfter: TimeInterval =
    2 * defaultHeartbeatInterval

  public static let defaultHandleAppLifecycle: Bool = {
    #if os(iOS) || os(macOS) || os(tvOS) || os(visionOS)
      return true
    #else
      return false
    #endif
  }()

  public init(
    headers: [String: String] = [:],
    heartbeatInterval: TimeInterval = Self.defaultHeartbeatInterval,
    reconnectDelay: TimeInterval = Self.defaultReconnectDelay,
    timeoutInterval: TimeInterval = Self.defaultTimeoutInterval,
    disconnectOnSessionLoss: Bool = Self.defaultDisconnectOnSessionLoss,
    connectOnSubscribe: Bool = Self.defaultConnectOnSubscribe,
    maxRetryAttempts: Int = Self.defaultMaxRetryAttempts,
    disconnectOnEmptyChannelsAfter: TimeInterval = Self.defaultDisconnectOnEmptyChannelsAfter,
    vsn: RealtimeProtocolVersion = .v2,
    handleAppLifecycle: Bool = Self.defaultHandleAppLifecycle,
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
    self.disconnectOnEmptyChannelsAfter = disconnectOnEmptyChannelsAfter
    self.vsn = vsn
    self.handleAppLifecycle = handleAppLifecycle
    self.logLevel = logLevel
    self.fetch = fetch
    self.accessToken = accessToken
    self.logger = logger
  }

  /// Backward-compatible initializer preserving the pre-`vsn` signature.
  /// Calls the primary initializer with `vsn: .v2`.
  @_disfavoredOverload
  public init(
    headers: [String: String] = [:],
    heartbeatInterval: TimeInterval = Self.defaultHeartbeatInterval,
    reconnectDelay: TimeInterval = Self.defaultReconnectDelay,
    timeoutInterval: TimeInterval = Self.defaultTimeoutInterval,
    disconnectOnSessionLoss: Bool = Self.defaultDisconnectOnSessionLoss,
    connectOnSubscribe: Bool = Self.defaultConnectOnSubscribe,
    maxRetryAttempts: Int = Self.defaultMaxRetryAttempts,
    disconnectOnEmptyChannelsAfter: TimeInterval = Self.defaultDisconnectOnEmptyChannelsAfter,
    logLevel: LogLevel? = nil,
    fetch: (@Sendable (_ request: URLRequest) async throws -> (Data, URLResponse))? = nil,
    accessToken: (@Sendable () async throws -> String?)? = nil,
    logger: (any SupabaseLogger)? = nil
  ) {
    self.init(
      headers: headers,
      heartbeatInterval: heartbeatInterval,
      reconnectDelay: reconnectDelay,
      timeoutInterval: timeoutInterval,
      disconnectOnSessionLoss: disconnectOnSessionLoss,
      connectOnSubscribe: connectOnSubscribe,
      maxRetryAttempts: maxRetryAttempts,
      disconnectOnEmptyChannelsAfter: disconnectOnEmptyChannelsAfter,
      vsn: .v2,
      logLevel: logLevel,
      fetch: fetch,
      accessToken: accessToken,
      logger: logger
    )
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
