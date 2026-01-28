import Foundation

/// A message sent over the Realtime WebSocket connection.
///
/// Both `joinRef` and `ref` are optional because certain messages like heartbeats
/// don't require a join reference as they don't refer to a specific channel.
public struct RealtimeMessageV2: Hashable, Codable, Sendable {
  /// Optional join reference. Nil for messages like heartbeats that don't belong to a specific channel.
  public let joinRef: String?
  /// Optional message reference. Can be nil for certain message types.
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

  /// Status for the received message if any.
  public var status: PushStatus? {
    payload["status"]
      .flatMap(\.stringValue)
      .flatMap(PushStatus.init(rawValue:))
  }

  var _eventType: EventType? {
    switch event {
    case ChannelEvent.system: .system
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
    case ChannelEvent.reply:
      .reply
    default:
      nil
    }
  }

  enum EventType {
    case system
    case postgresChanges
    case broadcast
    case close
    case error
    case presenceDiff
    case presenceState
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

extension RealtimeMessageV2: HasRawMessage {
  public var rawMessage: RealtimeMessageV2 { self }
}
