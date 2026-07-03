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
/// ### Event Classification
/// - ``eventType``
/// - ``EventType``
/// ### Initialization
/// - ``init(joinRef:ref:topic:event:payload:)``
public struct RealtimeMessageV2: Hashable, Codable, Sendable {
  /// The join reference that associates this message with the `phx_join` that opened the channel.
  ///
  /// `nil` for messages that are not scoped to a channel (e.g. heartbeats).
  public let joinRef: String?

  /// A unique reference string for this individual message, used to correlate replies.
  ///
  /// `nil` for server-pushed messages that do not expect a client reply.
  public let ref: String?

  /// The Realtime topic this message is addressed to (e.g. `"realtime:room:lobby"`).
  public let topic: String

  /// The Phoenix event name (e.g. `"phx_join"`, `"broadcast"`, `"postgres_changes"`).
  public let event: String

  /// The JSON payload carried by this message.
  public let payload: JSONObject

  /// Creates a new ``RealtimeMessageV2``.
  ///
  /// - Parameters:
  ///   - joinRef: The join reference, or `nil` for non-channel messages.
  ///   - ref: The message reference, or `nil` when no reply is expected.
  ///   - topic: The Realtime topic string.
  ///   - event: The Phoenix event name.
  ///   - payload: The JSON payload.
  public init(joinRef: String?, ref: String?, topic: String, event: String, payload: JSONObject) {
    self.joinRef = joinRef
    self.ref = ref
    self.topic = topic
    self.event = event
    self.payload = payload
  }

  /// The server reply status extracted from the payload, if present.
  ///
  /// Parsed from `payload["status"]`. Common values are `.ok` and `.error`.
  public var status: PushStatus? {
    payload["status"]
      .flatMap(\.stringValue)
      .flatMap(PushStatus.init(rawValue:))
  }

  /// The semantic event type parsed from ``event``.
  ///
  /// > Warning: Access to the structured event type will be removed in a future release. Inspect the raw ``event`` string directly instead.
  @available(
    *, deprecated,
    message: "Access to event type will be removed, please inspect raw event value instead."
  )
  public var eventType: EventType? { _eventType }

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

  /// A structured representation of the channel event type.
  ///
  /// > Warning: This enum is associated with the deprecated ``eventType`` property.
  /// > Inspect the raw ``event`` string instead of pattern-matching on this type.
  ///
  /// ## Topics
  /// ### Cases
  /// - ``system``
  /// - ``postgresChanges``
  /// - ``broadcast``
  /// - ``close``
  /// - ``error``
  /// - ``presenceDiff``
  /// - ``presenceState``
  /// - ``tokenExpired``
  /// - ``reply``
  public enum EventType {
    /// A channel-level system message (e.g. subscribe confirmation).
    case system

    /// A Postgres row change event.
    case postgresChanges

    /// A broadcast message from another client.
    case broadcast

    /// The channel was closed by the server.
    case close

    /// The server reported an error on this channel.
    case error

    /// A presence diff event describing joins and leaves.
    case presenceDiff

    /// A full presence state snapshot.
    case presenceState

    /// Token expiration event — now surfaced as a `system` event; check the payload for details.
    @available(
      *, deprecated,
      message:
        "tokenExpired gets returned as system, check payload for verifying if is a token expiration."
    )
    case tokenExpired

    /// A reply to a client-originated push.
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
