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
  var fetch:
    (
      @Sendable (
        _ request: HTTPRequest,
        _ bodyData: Data?
      ) async throws -> (Data, HTTPResponse)
    )?
  package var accessToken: (@Sendable () async throws -> String)?
  package var logger: (any SupabaseLogger)?

  public static let defaultHeartbeatInterval: TimeInterval = 15
  public static let defaultReconnectDelay: TimeInterval = 7
  public static let defaultTimeoutInterval: TimeInterval = 10
  public static let defaultDisconnectOnSessionLoss = true
  public static let defaultConnectOnSubscribe: Bool = true

  public init(
    headers: HTTPFields = [:],
    heartbeatInterval: TimeInterval = Self.defaultHeartbeatInterval,
    reconnectDelay: TimeInterval = Self.defaultReconnectDelay,
    timeoutInterval: TimeInterval = Self.defaultTimeoutInterval,
    disconnectOnSessionLoss: Bool = Self.defaultDisconnectOnSessionLoss,
    connectOnSubscribe: Bool = Self.defaultConnectOnSubscribe,
    fetch: (
      @Sendable (
        _ request: HTTPRequest,
        _ bodyData: Data?
      ) async throws -> (Data, HTTPResponse)
    )? = nil,
    accessToken: (@Sendable () async throws -> String)? = nil,
    logger: (any SupabaseLogger)? = nil
  ) {
    self.headers = headers
    self.heartbeatInterval = heartbeatInterval
    self.reconnectDelay = reconnectDelay
    self.timeoutInterval = timeoutInterval
    self.disconnectOnSessionLoss = disconnectOnSessionLoss
    self.connectOnSubscribe = connectOnSubscribe
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
