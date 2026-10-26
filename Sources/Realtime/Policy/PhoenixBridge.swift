//
//  PhoenixBridge.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

import Foundation
import Helpers
import Phoenix

extension Helpers.JSONValue {
  init(_ value: Phoenix.JSONValue) {
    switch value {
    case .null: self = .null
    case .bool(let bool): self = .bool(bool)
    case .int(let int): self = .integer(int)
    case .double(let double): self = .double(double)
    case .string(let string): self = .string(string)
    case .array(let array): self = .array(array.map(Helpers.JSONValue.init))
    case .object(let object): self = .object(object.mapValues(Helpers.JSONValue.init))
    }
  }

  var phoenix: Phoenix.JSONValue {
    switch self {
    case .null: .null
    case .bool(let bool): .bool(bool)
    case .integer(let int): .int(int)
    case .double(let double): .double(double)
    case .string(let string): .string(string)
    case .array(let array): .array(array.map(\.phoenix))
    case .object(let object): .object(object.mapValues(\.phoenix))
    }
  }
}

extension Dictionary where Key == String, Value == Helpers.JSONValue {
  init(_ object: Phoenix.JSONObject) {
    self = object.mapValues(Helpers.JSONValue.init)
  }

  var phoenix: Phoenix.JSONObject {
    mapValues(\.phoenix)
  }
}

extension Phoenix.Payload {
  var jsonObject: Helpers.JSONObject {
    json?.objectValue.map(Helpers.JSONObject.init) ?? [:]
  }
}

extension RealtimeClientStatus {
  init(_ status: SocketStatus) {
    switch status {
    case .disconnected: self = .disconnected
    case .connecting, .waitingToReconnect: self = .connecting
    case .connected: self = .connected
    }
  }
}

extension RealtimeChannelStatus {
  /// A channel holds an inner channel only while it wants to be joined, so `.unjoined` reads as
  /// subscribing.
  init(_ inner: ChannelStatus) {
    switch inner {
    case .unjoined, .joining, .errored: self = .subscribing
    case .joined: self = .subscribed
    case .leaving: self = .unsubscribing
    case .closed: self = .unsubscribed
    }
  }
}

extension HeartbeatStatus {
  init(_ event: HeartbeatEvent) {
    switch event {
    case .sent: self = .sent
    case .ok: self = .ok
    case .error: self = .error
    case .timeout: self = .timeout
    }
  }
}

extension RealtimeError {
  init(stoppedOn failure: SocketFailure) {
    switch failure {
    case .transport(let transport):
      if let status = transport.httpStatus {
        self = .upgradeFailed(status: status)
      } else {
        self = .transport("The WebSocket connection failed.")
      }
    case .closedByServer(let code, let reason):
      self = .socketClosed(code: code, reason: reason)
    case .heartbeatTimedOut:
      self = RealtimeError(kind: .timeout, message: "The server did not answer a heartbeat.")
    case .connectTimedOut:
      self = RealtimeError(kind: .timeout, message: "The WebSocket connection timed out.")
    case .codecRefusedHeartbeat:
      self = .transport("The client could not encode a heartbeat.")
    }
  }

  init(channelFailure error: any Error) {
    switch error {
    case let error as RealtimeError:
      self = error
    case ChannelError.rejected(let response):
      self = .joinError(reason: Self.reason(in: response) ?? "The server rejected the join.")
    case ChannelError.replyError(_, let response):
      self = .ackError(reason: Self.reason(in: response) ?? "The server rejected the push.")
    case ChannelError.timeout:
      self = RealtimeError(kind: .timeout, message: "The server did not reply in time.")
    case ChannelError.connectionLost:
      self = RealtimeError(
        kind: .notConnected, message: "The connection ended before the server replied.")
    case ChannelError.closed(.closedByServer):
      self = .channelClosedByServer
    case ChannelError.closed, ChannelError.joinNotCalled:
      self = .notSubscribed
    default:
      self = RealtimeError(
        kind: .encoding, message: "The channel could not encode the message.",
        isRetryable: false, underlyingError: error)
    }
  }

  /// The server's text in an error reply: `{"reason": ...}` for joins, `{"error": ...}` for a
  /// broadcast over the size limit, or a bare string.
  private static func reason(in response: Phoenix.Payload) -> String? {
    response.json?["reason"]?.stringValue ?? response.json?["error"]?.stringValue
      ?? response.json?.stringValue
  }
}

/// The WebSocket URL carries the API key in its query.
func redactingURLQueries(_ text: String) -> String {
  text.replacing(/((?:wss?|https?):\/\/[^\s?"']*)\?[^\s"']*/) { "\($0.output.1)?<redacted>" }
}
