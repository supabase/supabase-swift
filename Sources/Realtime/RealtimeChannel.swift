//
//  RealtimeChannel.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

public import Foundation
import Helpers

/// A Realtime channel that joins a topic and delivers its events as `AsyncStream`s.
///
/// Obtain an instance from ``RealtimeClient/channel(_:configure:)``, open the streams you want,
/// then call ``subscribe()``. Presence streams shape the join request, so open them **before**
/// subscribing. A Postgres changes stream opened after the join makes the channel rejoin with
/// the new binding. Broadcast and system streams can be opened at any time.
///
/// ```swift
/// let channel = await client.channel("room:lobby") { config in
///   config.broadcast.receiveOwnMessages = true
/// }
///
/// let messages = await channel.broadcasts(event: "message")
/// try await channel.subscribe()
///
/// for await message in messages {
///   print(try message.decode(as: ChatMessage.self))
/// }
/// ```
///
/// A channel is a handle: its client owns its state, so reads, stream methods, and actions are
/// `async`, one hop to the client each. A stream is registered by the time its method returns,
/// so it sees every event the next action causes. Two handles are equal only when they are the
/// same instance; the client keeps one per topic. Cancelling the task that iterates a stream
/// ends the stream and removes its listener; removing the channel ends every stream.
///
/// A removed channel, by ``RealtimeClient/removeChannel(_:)`` or by the server, is spent: its
/// actions throw ``RealtimeError/Kind-swift.struct/channelRemoved``, ``status`` reads
/// ``RealtimeChannelStatus/unsubscribed``, ``presenceState`` is empty, and new streams end at
/// once. Get a new channel from ``RealtimeClient/channel(_:configure:)``. A channel whose client
/// was released reads the same, and its actions throw an error of kind
/// ``RealtimeError/Kind-swift.struct/notConnected``. A handle cannot tell that it was removed
/// once its client is gone, so a removed channel whose client was released throws
/// ``RealtimeError/Kind-swift.struct/notConnected``, not
/// ``RealtimeError/Kind-swift.struct/channelRemoved``.
///
/// ## Topics
/// ### Identity
/// - ``topic``
/// - ``configuration``
/// ### Status
/// - ``status``
/// - ``statusChanges()``
/// ### Lifecycle
/// - ``subscribe()``
/// - ``unsubscribe()``
/// ### Broadcasting
/// - ``broadcast(event:payload:encoder:)``
/// - ``broadcast(event:data:)``
/// - ``httpSend(event:payload:encoder:timeout:)``
/// - ``httpSend(event:data:timeout:)``
/// ### Presence
/// - ``presenceState``
/// - ``presenceStates()``
/// - ``presenceChanges()``
/// - ``track(_:encoder:)``
/// - ``untrack()``
/// ### Postgres Changes
/// - ``postgresChanges(event:schema:table:filter:select:)``
/// - ``postgresChanges(of:event:schema:table:filter:select:decoder:)``
/// ### Broadcast Events
/// - ``broadcasts(event:)``
/// ### Channel Events
/// - ``events()``
public final class RealtimeChannel: Sendable, Hashable {
  /// The topic name passed to ``RealtimeClient/channel(_:configure:)``, such as `"room:lobby"`.
  ///
  /// The SDK adds the `realtime:` prefix the server expects on the WebSocket only.
  public let topic: String

  /// The identity of the channel in the core. The client issues it when it creates the channel.
  let id: ChannelID

  /// The topic on the WebSocket: ``topic`` with the `realtime:` prefix.
  let wireTopic: String

  /// The channel's configuration, as set in ``RealtimeClient/channel(_:configure:)``.
  public let configuration: RealtimeChannelConfiguration

  /// Weak: the client owns its channels' state, which holds this handle, and a channel the app
  /// keeps after releasing the client must not keep the client (and its socket) alive.
  var client: RealtimeClient? { clientReference.value }
  private let clientReference: WeakClient

  init(
    id: ChannelID,
    topic: String,
    configuration: RealtimeChannelConfiguration,
    client: RealtimeClient
  ) {
    self.id = id
    self.topic = topic
    self.wireTopic = Self.wireTopic(for: topic)
    self.configuration = configuration
    self.clientReference = WeakClient(value: client)
  }

  /// Two channels are equal only when they are the same instance.
  public static func == (lhs: RealtimeChannel, rhs: RealtimeChannel) -> Bool {
    lhs === rhs
  }

  /// Hashes the channel's identity, to match `==`.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }

  /// The client to run an action on. The client checks on its own actor whether the channel
  /// was removed.
  func clientForAction() throws(RealtimeError) -> RealtimeClient {
    guard let client else { throw .clientReleased }
    return client
  }

  // MARK: - Status

  /// The current subscription status of the channel.
  ///
  /// A removed channel, or one whose client was released, reads
  /// ``RealtimeChannelStatus/unsubscribed``. To follow the status, for example in a view, use
  /// ``statusChanges()``.
  public var status: RealtimeChannelStatus {
    get async { await client?.channelStatus(self) ?? .unsubscribed }
  }

  /// An async stream that emits channel subscription status changes.
  ///
  /// The stream is registered before this method returns. It first emits the status at that
  /// moment, then each later change, so no change between the call and the first iteration is
  /// lost. Cancelling the iterating task ends the stream; so does removing the
  /// channel from its client. On a removed channel, or one whose client was released, the
  /// stream ends at once.
  ///
  /// ```swift
  /// for await status in await channel.statusChanges() {
  ///   print("Channel status: \(status)")
  /// }
  /// ```
  public func statusChanges() async -> AsyncStream<RealtimeChannelStatus> {
    await client?.statusChanges(of: self) ?? .finished
  }

  // MARK: - Lifecycle

  /// Joins the Realtime topic and suspends until the subscription is confirmed by the server.
  ///
  /// Open the presence streams before calling this method; they shape the join request. A
  /// Postgres changes stream opened later makes the channel rejoin. Calling it on an
  /// already-subscribed channel is a no-op, and a second concurrent call waits for the first
  /// attempt instead of starting another.
  ///
  /// When the channel has Postgres changes streams, the method returns only once the server
  /// reports that those changes are live. If the server reports a failure, or does not report
  /// within ``RealtimeChannelConfiguration/PostgresChanges/subscriptionTimeout``, the channel
  /// leaves the topic and the method throws without a retry. The same holds for the rejoins the
  /// SDK starts itself, after a reconnect or for a new Postgres changes stream: the channel ends
  /// ``RealtimeChannelStatus/failed(_:)``. Watch ``statusChanges()`` and call this method again.
  ///
  /// When the server closes the channel (`phx_close`), the channel is spent, as after
  /// ``RealtimeClient/removeChannel(_:)``: a join in flight throws
  /// ``RealtimeError/Kind-swift.struct/channelClosedByServer``, and calling this method again on
  /// the same channel throws ``RealtimeError/Kind-swift.struct/channelRemoved``. Get a new
  /// channel from ``RealtimeClient/channel(_:configure:)``.
  ///
  /// There is no attempt limit. After a timeout, a lost connection, or a transient join error,
  /// the channel joins again after 1, 2 and 5 s, then every 10 s; after a rate limit it waits
  /// 30 s. An expired token gets one rejoin at once, with a token fetched again from the
  /// `accessToken` callback. Cancel the calling task to stop waiting: when no other caller
  /// waits for the join, the channel leaves the topic.
  ///
  /// - Throws: ``RealtimeError`` when a retry cannot help: the server refused the join for good
  ///   (``RealtimeError/isRetryable`` is `false`, for example ``RealtimeError/ServerCode/unauthorized``
  ///   from an RLS policy), the token was still expired after the rejoin, the server refused the
  ///   WebSocket upgrade, the client is disconnected and `connectOnSubscribe` is off,
  ///   ``RealtimeClient/disconnect(code:reason:)`` was called during the join, the server
  ///   could not set up the channel's Postgres changes in time, or the client was released
  ///   (``RealtimeError/Kind-swift.struct/notConnected``).
  ///   ``RealtimeError/Kind-swift.struct/channelClosedByServer`` when the server closed the
  ///   channel during the join, ``RealtimeError/Kind-swift.struct/channelRemoved`` when the
  ///   channel was removed or the server closed it earlier, and `CancellationError` when the
  ///   calling task is cancelled.
  public func subscribe() async throws {
    try await clientForAction().subscribe(self)
  }

  /// Leaves the Realtime topic and transitions the channel to
  /// ``RealtimeChannelStatus/unsubscribed``. Stops a subscribe in flight.
  ///
  /// The channel and its streams stay usable: call ``subscribe()`` to join again. Cancelling the
  /// calling task stops the wait, not the leave.
  ///
  /// On a removed channel, or one whose client was released, the method returns at once.
  public func unsubscribe() async {
    await client?.unsubscribe(self)
  }

  // MARK: - Broadcast

  /// Sends a broadcast message to every client on the channel, over the WebSocket.
  ///
  /// The channel must be subscribed. There is no fallback to the REST API; to broadcast without
  /// a subscription, use ``httpSend(event:payload:encoder:timeout:)``.
  ///
  /// Returns as soon as the frame is queued for the socket, unless
  /// ``RealtimeChannelConfiguration/Broadcast-swift.struct/acknowledge`` is on: then it waits for
  /// the server's reply. Wrap the call in a `Task` to send without waiting; cancelling that task
  /// stops the wait, not the frame. ``RealtimeClient/disconnect(code:reason:)`` still writes the
  /// frames queued before it, up to the client's request timeout; a lost connection drops them.
  ///
  /// > Important: On a private channel the server sends no reply when row level security denies
  /// > the write or the database fails. With `acknowledge` on, such a broadcast fails with
  /// > ``RealtimeError/Kind-swift.struct/timeout``.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - payload: The value to send. It must encode as a JSON object.
  ///   - encoder: The encoder for `payload`. Defaults to the encoder the SDK uses for requests.
  /// - Throws: An `EncodingError` when `payload` does not encode as a JSON object.
  ///   ``RealtimeError`` with kind ``RealtimeError/Kind-swift.struct/notSubscribed`` when the
  ///   channel is not subscribed, ``RealtimeError/Kind-swift.struct/timeout`` when no reply
  ///   arrived within the client's configured timeout, the server's reason as
  ///   ``RealtimeError/Kind-swift.struct/payloadTooLarge`` or
  ///   ``RealtimeError/Kind-swift.struct/server`` when it rejected the message,
  ///   ``RealtimeError/Kind-swift.struct/channelRemoved`` when the channel was removed,
  ///   ``RealtimeError/Kind-swift.struct/notConnected`` when the client was released, and
  ///   `CancellationError` when the awaiting task is cancelled.
  public func broadcast(
    event: String, payload: some Encodable, encoder: JSONEncoder = .supabase()
  ) async throws {
    let message = try JSONObject(payload, encoder: encoder)
    try await broadcast(event: event, payload: .json(message))
  }

  /// Sends a binary broadcast message over the WebSocket.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - data: Raw binary data to send as the payload.
  /// - Throws: The errors of ``broadcast(event:payload:encoder:)``, except the encoding error.
  public func broadcast(event: String, data: Data) async throws {
    try await broadcast(event: event, payload: .binary(data))
  }

  private func broadcast(event: String, payload: BroadcastPushPayload) async throws {
    try await clientForAction().broadcast(self, event: event, payload: payload)
  }

  // MARK: - Presence

  /// The clients present on the channel, as of the last presence sync.
  ///
  /// The state is empty until the first sync after ``subscribe()`` and after ``unsubscribe()``.
  /// After a rejoin it keeps the last known clients until the server sends the new state. A
  /// removed channel, or one whose client was released, reads an empty state. To follow the
  /// state, use ``presenceStates()``.
  public var presenceState: PresenceState {
    get async { await client?.presenceState(of: self) ?? PresenceState() }
  }

  /// Shares a payload with every client on the channel, under this client's presence key.
  ///
  /// Call this after ``subscribe()``. Calling it again replaces the payload. The server limits
  /// presence calls to five in 30 seconds, and the SDK sends each call as it comes, so throttle
  /// frequent updates in the app.
  ///
  /// The server forgets the payload when the channel leaves or the connection drops. The SDK
  /// does not send it again after a rejoin: call `track` again when ``events()`` emits
  /// ``RealtimeChannelEvent/resubscribed``.
  ///
  /// - Parameters:
  ///   - payload: The value to share. It must encode as a JSON object.
  ///   - encoder: The encoder for `payload`. Defaults to ``JSONValue/encoder`` when `nil`.
  /// - Throws: An error if `payload` does not encode as a JSON object,
  ///   ``RealtimeError/Kind-swift.struct/notSubscribed`` when the channel is not subscribed,
  ///   ``RealtimeError/Kind-swift.struct/timeout`` when the server does not reply in time, the
  ///   server's error when it rejects the call, ``RealtimeError/Kind-swift.struct/channelRemoved``
  ///   when the channel was removed, ``RealtimeError/Kind-swift.struct/notConnected`` when the
  ///   client was released, and `CancellationError` when the awaiting task is cancelled.
  public func track(_ payload: some Encodable, encoder: JSONEncoder? = nil) async throws {
    let payload = try JSONObject(payload, encoder: encoder ?? JSONValue.encoder)
    try await pushPresence([
      "type": "presence",
      "event": "track",
      "payload": .object(payload),
    ])
  }

  /// Removes this client's payload from the channel's presence.
  ///
  /// - Throws: The errors of ``track(_:encoder:)``, except the encoding error.
  public func untrack() async throws {
    try await pushPresence([
      "type": "presence",
      "event": "untrack",
    ])
  }

  private func pushPresence(_ payload: JSONObject) async throws {
    try await clientForAction().push(self, event: ChannelEvent.presence, payload: payload)
  }

  // MARK: - Helpers

  /// The `data` object of a `postgres_changes` payload, or `nil` when the payload has none.
  static func postgresChangeData(in payload: JSONObject) throws(RealtimeError) -> JSONObject? {
    guard let data = payload["data"] else { return nil }
    guard let object = data.objectValue else {
      throw RealtimeError.decoding("Expected \"data\" to be an object, got \(data).")
    }
    return object
  }

  /// Event names match exactly, case included, as the server sends them. `"*"` matches every
  /// event.
  static func eventMatches(_ listening: String, _ event: String) -> Bool {
    listening == "*" || listening == event
  }

  /// The topic on the WebSocket for the topic name `topic`.
  static func wireTopic(for topic: String) -> String {
    "realtime:\(topic)"
  }

  /// The topic name for a topic on the WebSocket, or `nil` when it is not a channel topic.
  static func topic(forWireTopic wireTopic: String) -> String? {
    guard wireTopic.hasPrefix("realtime:") else { return nil }
    return String(wireTopic.dropFirst("realtime:".count))
  }

  /// The waits between join attempts after a timeout, a lost connection, or a transient join
  /// error. The last step repeats.
  static let rejoinBackoff = BackoffPolicy.steps([
    .seconds(1), .seconds(2), .seconds(5), .seconds(10),
  ])

  /// The wait before the next join attempt after the server applied a rate limit.
  static let rateLimitBackoff: Duration = .seconds(30)
}

/// Holds a channel's client weakly. A `weak let` stored property does not compile with Swift 6.2,
/// which the package still supports.
private struct WeakClient: Sendable {
  weak var value: RealtimeClient?
}
