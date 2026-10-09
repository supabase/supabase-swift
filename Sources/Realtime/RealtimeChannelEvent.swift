//
//  RealtimeChannelEvent.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

/// Something that happened on a channel that is not a status change.
public enum RealtimeChannelEvent: Sendable {
  /// The channel joined again after losing its join. Events sent in between may be missed.
  case resubscribed
  /// The server attached the channel's postgres changes bindings.
  case postgresChangesReady
  /// The server could not attach the postgres changes bindings. The channel stays open, and the
  /// server may retry. The associated value is the server's message.
  case postgresChangesFailed(String)
  /// Any other `system` message.
  case serverMessage(RealtimeSystemMessage)
}

/// A `system` message the SDK does not turn into a status or a typed event.
public struct RealtimeSystemMessage: Sendable, Hashable {
  /// The status as the server sent it, such as `"ok"` or `"error"`. The server may add values.
  public var status: String
  /// The server's message text.
  public var message: String
  /// The server extension the message is about, such as `"postgres_changes"`.
  public var `extension`: String?
  /// The channel the message is about, as the server names it.
  public var channel: String?
}

extension RealtimeChannelEvent {
  /// A rejoin or a `system` message; `nil` for anything else.
  package init?(_ inbound: ChannelInbound) {
    switch inbound {
    case .resubscribed:
      self = .resubscribed
    case .message(let message) where message.event == "system":
      let payload = message.payload
      let status = payload["status"]?.stringValue ?? ""
      let text = payload["message"]?.stringValue ?? ""
      let `extension` = payload["extension"]?.stringValue
      if `extension` == "postgres_changes" {
        self = status == "ok" ? .postgresChangesReady : .postgresChangesFailed(text)
      } else {
        self = .serverMessage(
          RealtimeSystemMessage(
            status: status, message: text, extension: `extension`,
            channel: payload["channel"]?.stringValue))
      }
    case .message, .broadcast, .presenceChanged:
      return nil
    }
  }
}
