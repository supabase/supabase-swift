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

  public init(
    headers: [String: String] = [:],
    heartbeatInterval: TimeInterval = Self.defaultHeartbeatInterval,
    reconnectDelay: TimeInterval = Self.defaultReconnectDelay,
    timeoutInterval: TimeInterval = Self.defaultTimeoutInterval,
    disconnectOnSessionLoss: Bool = Self.defaultDisconnectOnSessionLoss,
    connectOnSubscribe: Bool = Self.defaultConnectOnSubscribe,
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

/// A broadcast event from the server.
///
/// If broadcast event was triggered using [`realtime.broadcast_changes`](https://supabase.com/docs/guides/realtime/subscribing-to-database-changes#using-broadcast),
/// use ``BroadcastEvent/broadcastChange(of:)`` to decode the payload into a specific type.
public struct BroadcastEvent: Codable, Hashable, Sendable {
  /// The type of the event, e.g. `broadcast`.
  public let type: String
  /// The event that triggered the broadcast.
  public let event: String
  /// The payload of the event.
  public let payload: JSONObject

  /// Decodes the payload into a specific type.
  ///
  /// If broadcast event was triggered using [`realtime.broadcast_changes`](https://supabase.com/docs/guides/realtime/subscribing-to-database-changes#using-broadcast),
  /// use this method to decode the payload into a specific type.
  public func broadcastChange() throws -> BroadcastChange {
    try payload.decode()
  }
}

/// A postgres change event sent through broadcast.
///
/// More info in [Subscribing to Database Changes](https://supabase.com/docs/guides/realtime/subscribing-to-database-changes)
public struct BroadcastChange: Codable, Sendable {
  /// The schema of the table that was changed.
  public var schema: String
  /// The table that was changed.
  public var table: String
  /// The operation that was performed on the table.
  public var operation: Operation

  /// The operation that was performed on the table.
  public enum Operation: Codable, Sendable {
    /// A new record was inserted.
    case insert(new: JSONObject)
    /// A record was updated.
    case update(new: JSONObject, old: JSONObject)
    /// A record was deleted.
    case delete(old: JSONObject)
  }
}

extension BroadcastChange {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: AnyCodingKey.self)

    self.schema = try container.decode(String.self, forKey: "schema")
    self.table = try container.decode(String.self, forKey: "table")
    self.operation = try BroadcastChange.Operation(from: decoder)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: AnyCodingKey.self)

    try container.encode(schema, forKey: "schema")
    try container.encode(table, forKey: "table")
    try operation.encode(to: encoder)
  }
}

extension BroadcastChange.Operation {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: AnyCodingKey.self)

    let operation = try container.decode(String.self, forKey: "operation")
    switch operation {
    case "INSERT":
      let new = try container.decode(JSONObject.self, forKey: "record")
      self = .insert(new: new)
    case "UPDATE":
      let new = try container.decode(JSONObject.self, forKey: "record")
      let old = try container.decode(JSONObject.self, forKey: "old_record")
      self = .update(new: new, old: old)
    case "DELETE":
      let old = try container.decode(JSONObject.self, forKey: "old_record")
      self = .delete(old: old)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: "operation",
        in: container,
        debugDescription: "Unknown operation type: \(operation)"
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: AnyCodingKey.self)

    switch self {
    case .insert(let new):
      try container.encode("INSERT", forKey: "operation")
      try container.encode(new, forKey: "record")
      try container.encodeNil(forKey: "old_record")
    case .update(let new, let old):
      try container.encode("UPDATE", forKey: "operation")
      try container.encode(new, forKey: "record")
      try container.encode(old, forKey: "old_record")
    case .delete(let old):
      try container.encode("DELETE", forKey: "operation")
      try container.encode(old, forKey: "old_record")
      try container.encodeNil(forKey: "record")
    }

  }
}
