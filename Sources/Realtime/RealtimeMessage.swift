import Foundation

/// A message exchanged over the Realtime WebSocket connection.
///
/// Both `joinRef` and `ref` are optional because certain messages (such as heartbeats)
/// are not scoped to a specific channel and therefore do not require join or message references.
///
/// ## Topics
/// ### Identity
/// - ``joinRef``
/// - ``ref``
/// - ``topic``
/// - ``event``
/// ### Payload
/// - ``payload``
/// - ``status``
/// ### Initialization
/// - ``init(joinRef:ref:topic:event:payload:)``
package struct RealtimeMessage: Hashable, Sendable {
  /// The join reference that associates this message with the `phx_join` that opened the channel.
  ///
  /// `nil` for messages that are not scoped to a channel (e.g. heartbeats).
  package let joinRef: String?

  /// A unique reference string for this individual message, used to correlate replies.
  ///
  /// `nil` for server-pushed messages that do not expect a client reply.
  package let ref: String?

  /// The Realtime topic this message is addressed to (e.g. `"realtime:room:lobby"`).
  package let topic: String

  /// The Phoenix event name (e.g. `"phx_join"`, `"broadcast"`, `"postgres_changes"`).
  package let event: String

  /// The JSON payload carried by this message.
  package let payload: JSONObject

  /// Creates a new ``RealtimeMessage``.
  ///
  /// - Parameters:
  ///   - joinRef: The join reference, or `nil` for non-channel messages.
  ///   - ref: The message reference, or `nil` when no reply is expected.
  ///   - topic: The Realtime topic string.
  ///   - event: The Phoenix event name.
  ///   - payload: The JSON payload.
  package init(joinRef: String?, ref: String?, topic: String, event: String, payload: JSONObject) {
    self.joinRef = joinRef
    self.ref = ref
    self.topic = topic
    self.event = event
    self.payload = payload
  }

  /// The server reply status extracted from the payload, if present.
  ///
  /// Parsed from `payload["status"]`. Common values are ``PushStatus/ok`` and
  /// ``PushStatus/error``.
  package var status: PushStatus? {
    payload["status"]
      .flatMap(\.stringValue)
      .map(PushStatus.init(rawValue:))
  }
}

/// The status the server put in a reply, as read by ``RealtimeMessage/status``.
///
/// A status this SDK has no member for is preserved in ``rawValue``.
package struct PushStatus: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  package let rawValue: String

  /// Creates a ``PushStatus`` from a raw string value.
  package init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``PushStatus`` from a string literal.
  package init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// The server acknowledged the push.
  package static let ok: PushStatus = "ok"

  /// The server rejected the push.
  package static let error: PushStatus = "error"
}
