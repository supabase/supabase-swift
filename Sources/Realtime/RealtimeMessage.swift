//
//  RealtimeMessage.swift
//
//
//  Created by Guilherme Souza on 11/01/24.
//

import Foundation
import Helpers

@available(*, deprecated, renamed: "RealtimeMessageV2")
public typealias RealtimeMessageV2 = RealtimeMessage

public struct RealtimeMessage: Hashable, Codable, Sendable {
  public let joinRef: String?
  public let ref: String?
  public let topic: String
  public let event: String
  public let payload: JSONObject

  public init(joinRef: String?, ref: String?, topic: String, event: String, payload: JSONObject) {
    self.joinRef = joinRef
    self.ref = ref
    self.topic = topic
    self.event = event
    self.payload = payload
  }

  var status: PushStatus? {
    payload["status"]
      .flatMap(\.stringValue)
      .flatMap(PushStatus.init(rawValue:))
  }

  public var eventType: EventType? {
    switch event {
    case ChannelEvent.system where status == .ok: .system
    case ChannelEvent.postgresChanges:
      .postgresChanges
    case ChannelEvent.broadcast:
      .broadcast
    case ChannelEvent.close:
      .close
    case ChannelEvent.error:
      .error
    case ChannelEvent.presenceDiff:
      .presenceDiff
    case ChannelEvent.presenceState:
      .presenceState
    case ChannelEvent.system
      where payload["message"]?.stringValue?.contains("access token has expired") == true:
      .tokenExpired
    case ChannelEvent.reply:
      .reply
    default:
      nil
    }
  }

  public enum EventType {
    case system
    case postgresChanges
    case broadcast
    case close
    case error
    case presenceDiff
    case presenceState
    case tokenExpired
    case reply
  }

  private enum CodingKeys: String, CodingKey {
    case joinRef = "join_ref"
    case ref
    case topic
    case event
    case payload
  }
}

extension RealtimeMessage: HasRawMessage {
  public var rawMessage: RealtimeMessage { self }
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
