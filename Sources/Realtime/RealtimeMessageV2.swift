import Foundation

/// A message exchanged over the Realtime WebSocket connection.
///
/// `joinRef` and `ref` are optional because some messages (such as heartbeats) are not scoped to
/// a channel and carry no join or message reference.
package struct RealtimeMessageV2: Hashable, Sendable {
  /// The join reference that associates this message with the `phx_join` that opened the channel.
  package let joinRef: String?

  /// A unique reference string for this message, used to correlate replies.
  package let ref: String?

  /// The Realtime topic this message is addressed to (e.g. `"realtime:room:lobby"`).
  package let topic: String

  /// The Phoenix event name (e.g. `"phx_join"`, `"broadcast"`, `"postgres_changes"`).
  package let event: String

  /// The JSON payload carried by this message.
  package let payload: JSONObject

  package init(joinRef: String?, ref: String?, topic: String, event: String, payload: JSONObject) {
    self.joinRef = joinRef
    self.ref = ref
    self.topic = topic
    self.event = event
    self.payload = payload
  }

  /// The status of a server reply, as carried in `payload["status"]`.
  package struct ReplyStatus: RawRepresentable, Hashable, Sendable {
    package let rawValue: String

    package init(rawValue: String) {
      self.rawValue = rawValue
    }

    package static let ok = ReplyStatus(rawValue: "ok")
    package static let error = ReplyStatus(rawValue: "error")
  }

  /// The reply status extracted from the payload, if present.
  package var status: ReplyStatus? {
    payload["status"]
      .flatMap(\.stringValue)
      .map(ReplyStatus.init(rawValue:))
  }
}
