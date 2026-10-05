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
      .map(PushStatus.init(rawValue:))
  }

  /// The ``event`` name as an ``EventType``.
  public var eventType: EventType {
    EventType(rawValue: event)
  }

  /// A channel event name, with static members for the events this SDK handles.
  ///
  /// The server can introduce new event names, so a `switch` over this value needs a `default:`
  /// case.
  ///
  /// ## Topics
  /// ### Events
  /// - ``system``
  /// - ``postgresChanges``
  /// - ``broadcast``
  /// - ``close``
  /// - ``error``
  /// - ``presenceDiff``
  /// - ``presenceState``
  /// - ``reply``
  public struct EventType: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    /// Creates a ``EventType`` from a raw string value.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Creates a ``EventType`` from a string literal.
    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// A channel-level system message (e.g. subscribe confirmation).
    public static let system = EventType(rawValue: ChannelEvent.system)

    /// A Postgres row change event.
    public static let postgresChanges = EventType(rawValue: ChannelEvent.postgresChanges)

    /// A broadcast message from another client.
    public static let broadcast = EventType(rawValue: ChannelEvent.broadcast)

    /// The channel was closed by the server.
    public static let close = EventType(rawValue: ChannelEvent.close)

    /// The server reported an error on this channel.
    public static let error = EventType(rawValue: ChannelEvent.error)

    /// A presence diff event describing joins and leaves.
    public static let presenceDiff = EventType(rawValue: ChannelEvent.presenceDiff)

    /// A full presence state snapshot.
    public static let presenceState = EventType(rawValue: ChannelEvent.presenceState)

    /// A reply to a client-originated push.
    public static let reply = EventType(rawValue: ChannelEvent.reply)
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
