//
//  Types.swift
//
//
//  Created by Guilherme Souza on 13/05/24.
//

import Foundation
import HTTPTypes
import Helpers

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
  var fetch: (@Sendable (_ request: URLRequest) async throws -> (Data, URLResponse))?
  package var logger: (any SupabaseLogger)?

  public static let defaultHeartbeatInterval: TimeInterval = 15
  public static let defaultReconnectDelay: TimeInterval = 7
  public static let defaultTimeoutInterval: TimeInterval = 10
  public static let defaultDisconnectOnSessionLoss = true
  public static let defaultConnectOnSubscribe: Bool = true

  public init(
    headers: [String: String] = [:],
    heartbeatInterval: TimeInterval = Self.defaultHeartbeatInterval,
    reconnectDelay: TimeInterval = Self.defaultReconnectDelay,
    timeoutInterval: TimeInterval = Self.defaultTimeoutInterval,
    disconnectOnSessionLoss: Bool = Self.defaultDisconnectOnSessionLoss,
    connectOnSubscribe: Bool = Self.defaultConnectOnSubscribe,
    fetch: (@Sendable (_ request: URLRequest) async throws -> (Data, URLResponse))? = nil,
    logger: (any SupabaseLogger)? = nil
  ) {
    self.headers = HTTPFields(headers)
    self.heartbeatInterval = heartbeatInterval
    self.reconnectDelay = reconnectDelay
    self.timeoutInterval = timeoutInterval
    self.disconnectOnSessionLoss = disconnectOnSessionLoss
    self.connectOnSubscribe = connectOnSubscribe
    self.fetch = fetch
    self.logger = logger
  }

  var apikey: String? {
    headers[.apiKey]
  }

  var accessToken: String? {
    guard let accessToken = headers[.authorization]?.split(separator: " ").last else {
      return nil
    }
    return String(accessToken)
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

extension HTTPField.Name {
  static let apiKey = Self("apiKey")!
}

/// Represents the different events that can be sent through
/// a channel regarding a Channel's lifecycle.
public enum ChannelEvent {
  public static let join = "phx_join"
  public static let leave = "phx_leave"
  public static let close = "phx_close"
  public static let error = "phx_error"
  public static let reply = "phx_reply"
  public static let system = "system"
  public static let broadcast = "broadcast"
  public static let accessToken = "access_token"
  public static let presence = "presence"
  public static let presenceDiff = "presence_diff"
  public static let presenceState = "presence_state"
  public static let postgresChanges = "postgres_changes"

  public static let heartbeat = "heartbeat"

  static func isLifecyleEvent(_ event: String) -> Bool {
    switch event {
    case join, leave, reply, error, close: true
    default: false
    }
  }
}
