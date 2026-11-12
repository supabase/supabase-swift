import ConcurrencyExtras
public import Foundation
internal import HTTPTypes
import Helpers
import IssueReporting

#if canImport(FoundationNetworking)
  import FoundationNetworking

  extension HTTPURLResponse {
    convenience init() {
      self.init(
        url: URL(string: "http://127.0.0.1")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
    }
  }
#endif

// cspell:ignore pvzp hhoc cnrp
/// How a ``RealtimeChannelV2`` joins its topic: privacy, broadcast and presence options.
///
/// Set the configuration in the closure you pass to ``RealtimeClientV2/channel(_:configure:)``.
///
/// ```swift
/// let channel = client.channel("room:lobby") { config in
///   config.isPrivate = true
///   config.broadcast.receivesOwnMessages = true
/// }
/// ```
///
/// ## Topics
/// ### Options
/// - ``broadcast-swift.property``
/// - ``presence-swift.property``
/// - ``isPrivate``
/// ### Option Groups
/// - ``Broadcast-swift.typealias``
/// - ``Presence-swift.typealias``
/// ### Initialization
/// - ``init()``
public struct RealtimeChannelConfiguration: Sendable, Hashable {
  /// Broadcast options of a channel.
  public typealias Broadcast = BroadcastJoinConfig

  /// Presence options of a channel.
  public typealias Presence = PresenceJoinConfig

  /// Broadcast options.
  public var broadcast: BroadcastJoinConfig

  /// Presence options.
  public var presence: PresenceJoinConfig

  /// Whether the channel is private.
  ///
  /// Private channels enforce access control via RLS policies defined in your database.
  /// See the [Realtime authorization guide](https://supabase.com/docs/guides/realtime/authorization)
  /// for details.
  public var isPrivate: Bool
}

extension RealtimeChannelConfiguration {
  /// Creates the default configuration: a public channel, with every option off.
  public init() {
    self.init(broadcast: BroadcastJoinConfig(), presence: PresenceJoinConfig(), isPrivate: false)
  }
}

/// The v2 name of ``RealtimeChannelConfiguration``.
@available(*, deprecated, renamed: "RealtimeChannelConfiguration")
public typealias RealtimeChannelConfig = RealtimeChannelConfiguration

protocol RealtimeChannelProtocol: AnyObject, Sendable {
  @MainActor var config: RealtimeChannelConfiguration { get }
  var topic: String { get }
  var logger: (any SupabaseLogger)? { get }

  var socket: any RealtimeClientProtocol { get }
}

/// A Realtime channel that joins a topic and dispatches incoming events to registered callbacks.
///
/// Obtain an instance from ``RealtimeClientV2/channel(_:configure:)`` and call
/// ``subscribeWithError()`` to start receiving events. Register all callbacks
/// **before** subscribing — adding callbacks after ``subscribe()``/``subscribeWithError()``
/// returns triggers a runtime warning.
///
/// ```swift
/// let channel = client.channel("room:lobby") { config in
///   config.broadcast.receivesOwnMessages = true
/// }
///
/// let messages = channel.broadcastStream(event: "message")
/// try await channel.subscribeWithError()
///
/// for await payload in messages {
///   print(payload)
/// }
/// ```
///
/// ## Topics
/// ### Identity
/// - ``topic``
/// - ``configuration``
/// - ``config``
/// ### Status
/// - ``status``
/// - ``statusChanges()``
/// - ``statusChange``
/// - ``onStatusChange(_:)``
/// ### Lifecycle
/// - ``subscribeWithError()``
/// - ``subscribe()``
/// - ``unsubscribe()``
/// ### Broadcasting
/// - ``broadcast(event:payload:encoder:)``
/// - ``broadcast(event:data:)``
/// - ``httpSend(event:payload:encoder:timeout:)``
/// - ``httpSend(event:data:timeout:)-(_,_,Duration?)``
/// ### Presence
/// - ``track(_:encoder:)``
/// - ``track(_:)``
/// - ``untrack()``
/// - ``onPresenceChange(_:)``
/// ### Postgres Changes
/// - ``onPostgresChange(_:schema:table:filter:callback:)-8kn76``
/// - ``onPostgresChange(_:schema:table:filter:callback:)-1j0l6``
/// - ``onPostgresChange(_:schema:table:filter:callback:)-9c5h2``
/// - ``onPostgresChange(_:schema:table:filter:callback:)-7srl6``
/// ### Broadcast Events
/// - ``onBroadcast(event:callback:)``
/// - ``onBroadcastData(event:callback:)``
/// ### System Events
/// - ``onSystem(callback:)-7cnrp``
/// - ``onSystem(callback:)-7cno3``
/// ### Deprecated
/// - ``updateAuth(jwt:)``
public final class RealtimeChannelV2: Sendable, RealtimeChannelProtocol {
  /// The fully-qualified topic string sent to the Realtime server (e.g. `"realtime:room:lobby"`).
  public let topic: String

  /// The channel's topic without the `realtime:` prefix, as expected by the
  /// broadcast REST endpoint (WebSocket frames use the full ``topic``).
  let subTopic: String

  /// The configuration the channel was created with.
  ///
  /// Reflects the closure passed to ``RealtimeClientV2/channel(_:configure:)``.
  ///
  /// > Note: On this version the property is isolated to the main actor. v3 makes it nonisolated.
  @MainActor public private(set) var configuration: RealtimeChannelConfiguration

  /// The channel's current configuration.
  @available(*, deprecated, message: "Use configuration instead.")
  @MainActor public var config: RealtimeChannelConfiguration { configuration }

  let logger: (any SupabaseLogger)?
  let socket: any RealtimeClientProtocol

  let stateManager: ChannelStateManager
  let callbackManager = CallbackManager()

  /// Buffer of `postgres_changes` filters registered via
  /// ``onPostgresChange`` prior to ``subscribe()``. Lives on the channel
  /// (not on ``stateManager``) so the synchronous `onPostgresChange` API
  /// can append without a fire-and-forget `Task` — which would race with
  /// a subsequent `subscribe()` call and sometimes lose the filter.
  let clientChanges = LockIsolated<[PostgresJoinConfig]>([])

  /// Lock-protected status + subscribers for ``status``/``statusChanges()``.
  /// See `RealtimeChannel+Status.swift`.
  let statusStorage = LockIsolated(StatusStorage())

  init(
    topic: String,
    config: RealtimeChannelConfiguration,
    socket: any RealtimeClientProtocol,
    logger: (any SupabaseLogger)?
  ) {
    self.topic = topic
    self.subTopic =
      topic.hasPrefix("realtime:") ? String(topic.dropFirst("realtime:".count)) : topic
    self.configuration = config
    self.logger = logger
    self.socket = socket

    let weakSelfRef = WeakChannelRef()
    let clientChanges = self.clientChanges
    self.stateManager = ChannelStateManager(
      topic: topic,
      logger: logger,
      maxRetryAttempts: socket.options.maxRetryAttempts,
      timeoutInterval: socket.options.timeoutInterval,
      clock: socket.clock,
      makeRef: { [socket] in socket.makeRef() },
      ensureSocketConnected: { [weak socket] in
        guard let socket else { return false }
        if socket.status == .connected { return true }
        guard socket.options.connectOnSubscribe else {
          reportIssue(
            "You can't subscribe to a channel while the realtime client is not connected. Did you forget to call `realtime.connect()`?"
          )
          return false
        }
        await socket.connect()
        return socket.status == .connected
      },
      isSocketConnected: { [weak socket] in socket?.status == .connected },
      getClientChanges: { clientChanges.value },
      joinOperation: { [weakSelfRef] ref, changes in
        guard let channel = weakSelfRef.value else { return }
        await channel.performJoin(ref: ref, clientChanges: changes)
      },
      leaveOperation: { [weakSelfRef] in
        guard let channel = weakSelfRef.value else { return }
        await channel.push(ChannelEvent.leave)
      },
      stateDidChange: { [weakSelfRef] state in
        // Forward every state-machine transition to the public status
        // storage synchronously. Running this on the actor avoids the
        // async observer-Task delay, so reads of ``status`` right after
        // ``subscribe()`` returns see the latest value.
        weakSelfRef.value?.yieldStatus(Self.mapState(state))
      }
    )

    weakSelfRef.value = self
  }

  deinit {
    callbackManager.reset()
    let continuations = statusStorage.withValue {
      storage -> [AsyncStream<RealtimeChannelStatus>.Continuation] in
      defer { storage.continuations.removeAll() }
      return storage.continuations.map { $1 }
    }
    for continuation in continuations {
      continuation.finish()
    }
  }

  private static func mapState(_ state: ChannelStateManager.State) -> RealtimeChannelStatus {
    switch state {
    case .unsubscribed: .unsubscribed
    case .subscribing: .subscribing
    case .subscribed: .subscribed
    case .unsubscribing: .unsubscribing
    }
  }

  /// Joins the Realtime topic and suspends until the subscription is confirmed by the server.
  ///
  /// All callbacks (broadcast, presence, postgres changes) must be registered before calling
  /// this method. Calling it more than once on an already-subscribed channel is a no-op.
  ///
  /// A channel removed from its client, or closed by the server, never joins again; get a new one
  /// from ``RealtimeClientV2/channel(_:configure:)``.
  ///
  /// - Throws: A ``RealtimeError`` if the subscribe attempt fails or times out;
  ///   `CancellationError` when an ``unsubscribe()`` or a removal stops it, or when the channel
  ///   was already removed.
  public func subscribeWithError() async throws {
    logger?.debug("Subscribe requested for channel '\(topic)'")
    try await stateManager.subscribe()
  }

  /// Joins the Realtime topic, silently ignoring any errors.
  ///
  /// > Warning: Prefer ``subscribeWithError()`` so errors are surfaced to the caller.
  @available(*, deprecated, message: "Use `subscribeWithError` instead")
  @MainActor
  public func subscribe() async {
    try? await subscribeWithError()
  }

  /// Leaves the Realtime topic and transitions the channel to ``RealtimeChannelStatus/unsubscribed``.
  public func unsubscribe() async {
    logger?.debug("Unsubscribe requested for channel '\(topic)'")
    await stateManager.unsubscribe()
  }

  /// Resets the channel for a rejoin. Returns whether it should rejoin.
  @discardableResult
  func resetForReconnect() async -> Bool {
    await stateManager.resetForReconnect()
  }

  /// Resets the channel after a reconnect and joins again if the caller still wants it joined.
  func rejoinAfterReconnect() async throws {
    try await stateManager.rejoinAfterReconnect()
  }

  /// Unsubscribes the channel for its removal from the client; it never joins again.
  func unsubscribeForRemoval() async {
    await stateManager.unsubscribeForRemoval()
  }

  /// Build the `phx_join` payload from the current config and push it.
  /// Invoked by ``ChannelStateManager`` via the ``ChannelStateManager/JoinOperation``
  /// closure at the moment the state machine is ready to join.
  @MainActor
  private func performJoin(ref: String, clientChanges: [PostgresJoinConfig]) async {
    logger?.debug("Sending phx_join for channel '\(topic)' (ref: \(ref))")

    configuration.presence.enabled = callbackManager.callbacks.contains(where: { $0.isPresence })

    let joinConfig = RealtimeJoinConfig(
      broadcast: configuration.broadcast,
      presence: configuration.presence,
      postgresChanges: clientChanges,
      isPrivate: configuration.isPrivate
    )

    let payload = RealtimeJoinPayload(
      config: joinConfig,
      accessToken: await socket._getAccessToken(),
      version: socket.options.headers[.xClientInfo]
    )

    await push(
      ChannelEvent.join,
      ref: ref,
      payload: try! JSONObject(payload)
    )
  }

  /// Updates the JWT token for this channel directly.
  ///
  /// > Warning: Updating the token per-channel is deprecated. Use
  /// > ``RealtimeClientV2/setAuth(_:)`` on the client instead.
  @available(
    *,
    deprecated,
    message:
      "manually updating auth token per channel is not recommended, please use `setAuth` in RealtimeClient instead."
  )
  public func updateAuth(jwt: String?) async {
    logger?.debug("Updating auth token for channel \(topic)")
    await push(
      ChannelEvent.accessToken,
      payload: ["access_token": jwt.map { .string($0) } ?? .null]
    )
  }

  /// Sends a broadcast message via the REST API.
  ///
  /// This method always targets the REST broadcast endpoint regardless of the current
  /// WebSocket state. Use it when you need guaranteed REST delivery or want to send
  /// a broadcast before subscribing to the channel.
  ///
  /// > Important: Requires a Realtime server version >= 2.97.0. Older servers don't expose
  /// > the per-event `/api/broadcast/{topic}/events/{event}` endpoint this method targets.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - payload: The value to send as the JSON request body.
  ///   - encoder: The encoder for `payload`. `nil` uses `AnyJSON.encoder`.
  ///   - timeout: How long the request may take. `nil` uses the client's configured timeout.
  /// - Throws: ``RealtimeError`` with kind `.invalidRequest` when `payload` does not encode or
  ///   the client has no access token, and nothing is sent; `.server` when the server does not
  ///   accept the message.
  ///
  /// > Note: v3 sends the request without a token when the client has none, counts the token
  /// > fetch in the timeout, and reports a timeout as a ``RealtimeError``. This version does not.
  public func httpSend(
    event: String,
    payload: some Encodable,
    encoder: JSONEncoder? = nil,
    timeout: Duration? = nil
  ) async throws {
    let body: Data
    do {
      body = try (encoder ?? AnyJSON.encoder).encode(payload)
    } catch {
      throw RealtimeError.invalidRequest(
        "The payload cannot be encoded as JSON.", underlyingError: error)
    }
    try await _httpSend(
      event: event, body: body, contentType: "application/json", timeout: timeout?.timeInterval)
  }

  /// Sends a broadcast message via the REST API using a `Codable` payload.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - message: A `Codable` value to send as the message payload.
  ///   - timeout: An optional timeout in seconds. Defaults to the socket's configured timeout.
  /// - Throws: A ``RealtimeError`` if the access token is missing or the request fails.
  @available(*, deprecated, message: "Use httpSend(event:payload:encoder:timeout:) instead.")
  public func httpSend(
    event: String,
    message: some Codable,
    timeout: TimeInterval? = nil
  ) async throws {
    try await _httpSend(event: event, message: JSONObject(message), timeout: timeout)
  }

  /// Sends a broadcast message via the REST API using a raw `JSONObject` payload.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - message: A ``JSONObject`` to send as the message payload.
  ///   - timeout: An optional timeout in seconds. Defaults to the socket's configured timeout.
  /// - Throws: A ``RealtimeError`` if the access token is missing or the request fails.
  @available(*, deprecated, message: "Use httpSend(event:payload:encoder:timeout:) instead.")
  public func httpSend(
    event: String,
    message: JSONObject,
    timeout: TimeInterval? = nil
  ) async throws {
    try await _httpSend(event: event, message: message, timeout: timeout)
  }

  private func _httpSend(event: String, message: JSONObject, timeout: TimeInterval?) async throws {
    guard let accessToken = await socket._getAccessToken() else {
      throw RealtimeError.invalidRequest("Access token is required for httpSend()")
    }
    try await _httpSend(
      event: event,
      body: JSONEncoder.supabase().encode(message),
      contentType: "application/json",
      timeout: timeout,
      accessToken: accessToken
    )
  }

  /// Sends a binary broadcast message via the REST API.
  ///
  /// This method always targets the REST broadcast endpoint regardless of the current
  /// WebSocket state. The payload is sent as-is with an `application/octet-stream`
  /// content type — use this for raw binary payloads (e.g. images, custom binary formats)
  /// that shouldn't be JSON-encoded.
  ///
  /// > Important: Requires a Realtime server version >= 2.97.0.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - data: Raw binary data to send as the request body.
  ///   - timeout: How long the request may take. `nil` uses the client's configured timeout.
  /// - Throws: ``RealtimeError`` with kind `.invalidRequest` when the client has no access token,
  ///   and nothing is sent; `.server` when the server does not accept the message.
  public func httpSend(
    event: String,
    data: Data,
    timeout: Duration? = nil
  ) async throws {
    try await _httpSend(
      event: event, body: data, contentType: "application/octet-stream",
      timeout: timeout?.timeInterval)
  }

  /// Sends a binary broadcast message via the REST API.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - data: Raw binary data to send as the request body.
  ///   - timeout: An optional timeout in seconds. Defaults to the socket's configured timeout.
  /// - Throws: A ``RealtimeError`` if the access token is missing or the request fails.
  @available(
    *, deprecated, message: "Use httpSend(event:data:timeout:) with a Duration instead."
  )
  @_disfavoredOverload
  public func httpSend(
    event: String,
    data: Data,
    timeout: TimeInterval? = nil
  ) async throws {
    try await _httpSend(
      event: event, body: data, contentType: "application/octet-stream", timeout: timeout)
  }

  private func _httpSend(
    event: String,
    body: Data,
    contentType: String,
    timeout: TimeInterval?,
    accessToken: String? = nil
  ) async throws {
    var accessToken = accessToken
    if accessToken == nil {
      accessToken = await socket._getAccessToken()
    }
    guard let accessToken else {
      throw RealtimeError.invalidRequest("Access token is required for httpSend()")
    }

    let isPrivate = await configuration.isPrivate

    var headers: HTTPFields = [.contentType: contentType]
    if let apiKey = socket.options.apikey {
      headers[.apiKey] = apiKey
    }
    headers[.authorization] = "Bearer \(accessToken)"

    let request = HTTPRequest(
      url: socket.broadcastURL(topic: subTopic, event: event, isPrivate: isPrivate),
      method: .post,
      headers: headers,
      body: body
    )

    let response = try await withTimeout(
      interval: timeout ?? socket.options.timeoutInterval, clock: socket.clock
    ) {
      [self] in try await socket.http.send(request)
    }

    try Self.validateHTTPSendResponse(response)
  }

  private static func validateHTTPSendResponse(_ response: Helpers.HTTPResponse) throws {
    guard response.statusCode == 202 else {
      // Try to parse error message from response body
      var errorMessage = HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
      if let errorBody = try? response.decoded(as: [String: String].self) {
        errorMessage = errorBody["error"] ?? errorBody["message"] ?? errorMessage
      }
      throw RealtimeError(errorMessage)
    }
  }

  /// Sends a broadcast message over the WebSocket.
  ///
  /// When the channel is subscribed, the message goes over the WebSocket connection. When it is
  /// not, the call falls back to the REST broadcast endpoint and reports an issue. Prefer
  /// ``httpSend(event:payload:encoder:timeout:)`` for an explicit REST call.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - payload: The value to send. It must encode to a JSON object.
  ///   - encoder: The encoder for `payload`. `nil` uses `AnyJSON.encoder`.
  /// - Throws: ``RealtimeError`` with kind `.invalidRequest` when `payload` does not encode to a
  ///   JSON object. Nothing is sent.
  ///
  /// > Note: v3 throws `.notSubscribed` when the channel is not subscribed, takes any JSON value
  /// > as the payload, and throws when the server rejects an acknowledged message. This version
  /// > does none of these.
  public func broadcast(
    event: String,
    payload: some Encodable,
    encoder: JSONEncoder? = nil
  ) async throws {
    await _broadcast(event: event, message: try Self.jsonObject(payload, encoder: encoder))
  }

  /// Sends a broadcast message with a `Codable` payload over WebSocket (or falls back to REST).
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - message: A `Codable` value to send as the message payload.
  @available(*, deprecated, message: "Use broadcast(event:payload:encoder:) instead.")
  public func broadcast(event: String, message: some Codable) async throws {
    try await _broadcast(event: event, message: JSONObject(message))
  }

  /// Sends a broadcast message with a raw `JSONObject` payload over WebSocket (or falls back to REST).
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - message: A raw ``JSONObject`` payload.
  @available(*, deprecated, message: "Use broadcast(event:payload:encoder:) instead.")
  @MainActor
  public func broadcast(event: String, message: JSONObject) async {
    await _broadcast(event: event, message: message)
  }

  /// Encodes `payload` and reads it back as the JSON object the v2 wire format carries.
  private static func jsonObject(
    _ payload: some Encodable, encoder: JSONEncoder?
  ) throws -> JSONObject {
    let json: AnyJSON
    do {
      let data = try (encoder ?? AnyJSON.encoder).encode(payload)
      json = try AnyJSON.decoder.decode(AnyJSON.self, from: data)
    } catch {
      throw RealtimeError.invalidRequest(
        "The payload cannot be encoded as JSON.", underlyingError: error)
    }
    guard let object = json.objectValue else {
      throw RealtimeError.invalidRequest("The payload must encode to a JSON object.")
    }
    return object
  }

  @MainActor
  private func _broadcast(event: String, message: JSONObject) async {
    if status != .subscribed {
      // Properly expecting issues during tests isn't working as expected, I think because the reportIssue is usually triggered inside an unstructured Task
      // because of this I'm disabling issue reporting during tests, so we can use it only for advising developers when running their applications.
      if !isTesting {
        reportIssue(
          """
          Realtime broadcast() is automatically falling back to REST API.
          This behavior will be deprecated in the future.
          Please use httpSend() explicitly for REST delivery.
          """
        )
      }

      var headers: HTTPFields = [.contentType: "application/json"]
      if let apiKey = socket.options.apikey {
        headers[.apiKey] = apiKey
      }
      if let accessToken = await socket._getAccessToken() {
        headers[.authorization] = "Bearer \(accessToken)"
      }

      let task = Task { [headers] in
        _ = try? await socket.http.send(
          HTTPRequest(
            url: socket.broadcastURL(
              topic: subTopic, event: event, isPrivate: configuration.isPrivate),
            method: .post,
            headers: headers,
            body: JSONEncoder.supabase().encode(message)
          )
        )
      }

      if configuration.broadcast.acknowledgesMessages {
        try? await withTimeout(interval: socket.options.timeoutInterval, clock: socket.clock) {
          await task.value
        }
      }
    } else {
      switch socket.options.vsn {
      case .v1:
        await push(
          ChannelEvent.broadcast,
          payload: [
            "type": "broadcast",
            "event": .string(event),
            "payload": .object(message),
          ]
        )
      case .v2:
        let joinRef = await stateManager.joinRef
        socket.pushBroadcast(
          joinRef: joinRef,
          ref: socket.makeRef(),
          topic: topic,
          event: event,
          jsonPayload: message
        )
      }
    }
  }

  /// Sends a binary broadcast message over WebSocket.
  ///
  /// Binary broadcasts require protocol version ``RealtimeProtocolVersion/v2`` and an active
  /// subscription. An issue is reported (via `reportIssue`) if the channel is not subscribed or
  /// if the client is running protocol 1.0.0.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name.
  ///   - data: Raw binary data to send as the payload.
  @MainActor
  public func broadcast(event: String, data: Data) async {
    if status != .subscribed {
      if !isTesting {
        reportIssue(
          "You can only send binary broadcasts after subscribing to the channel. Did you forget to call `channel.subscribe()`?"
        )
      }
      return
    }

    if socket.options.vsn == .v1 {
      if !isTesting {
        reportIssue(
          "Binary broadcast requires protocol version 2.0.0. Set `vsn: .v2` in RealtimeClientOptions."
        )
      }
      return
    }

    let joinRef = await stateManager.joinRef
    socket.pushBroadcast(
      joinRef: joinRef,
      ref: socket.makeRef(),
      topic: topic,
      event: event,
      binaryPayload: data
    )
  }

  /// Tracks this client's presence on the channel.
  ///
  /// The payload is shared with all other clients on the same channel. Call this after
  /// subscribing.
  ///
  /// - Parameters:
  ///   - payload: The value to track. It must encode to a JSON object.
  ///   - encoder: The encoder for `payload`. `nil` uses `AnyJSON.encoder`.
  /// - Throws: ``RealtimeError`` with kind `.invalidRequest` when `payload` does not encode to a
  ///   JSON object. Nothing is sent.
  ///
  /// > Note: v3 throws `.notSubscribed` when the channel is not subscribed. This version reports
  /// > an issue and sends the message.
  public func track(_ payload: some Encodable, encoder: JSONEncoder? = nil) async throws {
    await _track(state: try Self.jsonObject(payload, encoder: encoder))
  }

  /// Tracks the current client's presence state using a `Codable` value.
  ///
  /// The state is shared with all other clients on the same channel. Call this after subscribing.
  ///
  /// - Parameter state: A `Codable` value representing the client's presence state.
  /// - Throws: An error if the state cannot be encoded.
  public func track(_ state: some Codable) async throws {
    try await _track(state: JSONObject(state))
  }

  /// Tracks the current client's presence state using a raw `JSONObject`.
  ///
  /// The state is shared with all other clients on the same channel. Call this after subscribing.
  ///
  /// - Parameter state: A ``JSONObject`` representing the client's presence state.
  @available(*, deprecated, message: "Use track(_:encoder:) instead.")
  public func track(state: JSONObject) async {
    await _track(state: state)
  }

  private func _track(state: JSONObject) async {
    if status != .subscribed {
      reportIssue(
        "You can only track your presence after subscribing to the channel. Did you forget to call `channel.subscribe()`?"
      )
    }

    await push(
      ChannelEvent.presence,
      payload: [
        "type": "presence",
        "event": "track",
        "payload": .object(state),
      ]
    )
  }

  /// Stops tracking the current client's presence state on the channel.
  public func untrack() async {
    await push(
      ChannelEvent.presence,
      payload: [
        "type": "presence",
        "event": "untrack",
      ]
    )
  }

  func onMessage(_ message: RealtimeMessageV2) async {
    do {
      guard let eventType = message._eventType else {
        logger?.debug("Received message without event type: \(message)")
        return
      }

      switch eventType {
      case .tokenExpired:
        // deprecated type
        break

      case .system:
        if message.status == .ok {
          await stateManager.didReceiveSubscribedOK()
        } else {
          logger?.debug(
            "Failed to subscribe to channel \(message.topic): \(message.payload)"
          )
        }

        callbackManager.triggerSystem(message: message)

      case .reply:
        guard
          let ref = message.ref,
          let status = message.payload["status"]?.stringValue
        else {
          throw RealtimeError.decoding("Received a reply with unexpected payload: \(message)")
        }

        await didReceiveReply(ref: ref, status: status)

        if message.payload["response"]?.objectValue?.keys
          .contains(ChannelEvent.postgresChanges) == true
        {
          let serverPostgresChanges = try message.payload["response"]?
            .objectValue?["postgres_changes"]?
            .decode(as: [PostgresJoinConfig].self)

          callbackManager.setServerChanges(changes: serverPostgresChanges ?? [])
          await stateManager.didReceiveSubscribedOK()
        }

      case .postgresChanges:
        guard let data = message.payload["data"] else {
          logger?.debug("Expected \"data\" key in message payload.")
          return
        }

        let ids = message.payload["ids"]?.arrayValue?.compactMap(\.intValue) ?? []

        let postgresActions = try data.decode(as: PostgresActionData.self)

        let action: AnyAction
        switch postgresActions.type {
        case "UPDATE":
          action = .update(
            UpdateAction(
              columns: postgresActions.columns,
              commitTimestamp: postgresActions.commitTimestamp,
              record: postgresActions.record ?? [:],
              oldRecord: postgresActions.oldRecord ?? [:],
              rawMessage: message
            )
          )

        case "DELETE":
          action = .delete(
            DeleteAction(
              columns: postgresActions.columns,
              commitTimestamp: postgresActions.commitTimestamp,
              oldRecord: postgresActions.oldRecord ?? [:],
              rawMessage: message
            )
          )

        case "INSERT":
          action = .insert(
            InsertAction(
              columns: postgresActions.columns,
              commitTimestamp: postgresActions.commitTimestamp,
              record: postgresActions.record ?? [:],
              rawMessage: message
            )
          )

        default:
          throw RealtimeError.decoding("Unknown event type: \(postgresActions.type)")
        }

        callbackManager.triggerPostgresChanges(ids: ids, data: action)

      case .broadcast:
        let payload = message.payload

        guard let event = payload["event"]?.stringValue else {
          throw RealtimeError.decoding("Expected 'event' key in 'payload' for broadcast event.")
        }

        callbackManager.triggerBroadcast(event: event, json: payload)

      case .close:
        // Phoenix tags `phx_close` with the `join_ref` of the join it closes.
        // A close for a previous incarnation of this topic (e.g. a join
        // abandoned during a reconnect) must not tear down the current
        // subscription (issue #1145, defect 3). The join_ref check runs on
        // the state-manager actor, atomically with the close, so a concurrent
        // subscribe attempt can't swap `joinRef` in between. The same turn
        // marks the channel removed: a reconnect or a `subscribe()` must never
        // join it once `_remove` has unmapped it.
        guard
          await stateManager.didReceiveClose(joinRef: message.joinRef, removesChannel: true)
        else {
          return
        }
        socket._remove(self)

      case .error:
        logger?.error(
          "Received an error in channel \(message.topic). That could be as a result of an invalid access token"
        )
        // Like `phx_close`, `phx_error` is tagged with the `join_ref` of the
        // join it belongs to — an error from a stale join must not tear down
        // the current subscription (#1148). Errors without a `join_ref`
        // (e.g. auth errors before a join completes) are applied
        // unconditionally.
        await stateManager.didReceiveClose(joinRef: message.joinRef)

      case .presenceDiff:
        let joins = try message.payload["joins"]?.decode(as: [String: PresenceV2].self) ?? [:]
        let leaves = try message.payload["leaves"]?.decode(as: [String: PresenceV2].self) ?? [:]
        callbackManager.triggerPresenceDiffs(joins: joins, leaves: leaves, rawMessage: message)

      case .presenceState:
        let joins = try message.payload.decode(as: [String: PresenceV2].self)
        callbackManager.triggerPresenceDiffs(joins: joins, leaves: [:], rawMessage: message)
      }
    } catch {
      logger?.debug("Failed: \(error)")
    }
  }

  /// Called by the client when a binary broadcast frame (type 0x04) is received.
  func handleBinaryBroadcast(_ broadcast: DecodedBroadcast) async {
    let event = broadcast.event

    switch broadcast.payload {
    case .json(let json):
      // Route JSON payload to existing JSON broadcast callbacks.
      callbackManager.triggerBroadcast(
        event: event,
        json: [
          "event": .string(event),
          "payload": .object(json),
          "type": "broadcast",
        ]
      )

    case .binary(let data):
      if callbackManager.hasBroadcastDataCallbacks(for: event) {
        callbackManager.triggerBroadcastData(event: event, data: data)
      } else {
        logger?.warning(
          "Received binary broadcast for event '\(event)' but no Data callbacks are registered. "
            + "Register a callback with onBroadcastData(event:callback:) to receive Data."
        )
      }
    }
  }

  /// Registers a closure that is called when clients join or leave the channel's presence set.
  ///
  /// Register this callback before calling ``subscribeWithError()``.
  ///
  /// ```swift
  /// let subscription = channel.onPresenceChange { action in
  ///   print("joins:", action.joins, "leaves:", action.leaves)
  /// }
  /// ```
  ///
  /// > Note: Use ``presenceChange()`` if you prefer async iteration over closures.
  ///
  /// - Parameter callback: A `@Sendable` closure receiving a ``PresenceAction`` value.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  public func onPresenceChange(
    _ callback: @escaping @Sendable (any PresenceAction) -> Void
  ) -> RealtimeSubscription {
    guard status != .subscribed && status != .subscribing else {
      // See the comment on `broadcast(event:message:)` for why this is gated on `isTesting`.
      if !isTesting {
        reportIssue(
          """
          Cannot add "presence" callbacks for "\(topic)" after `subscribe()`.
          Please add all your presence callbacks before subscribing to the channel.
          """
        )
      }
      return RealtimeSubscription {}
    }

    let id = callbackManager.addPresenceCallback(callback: callback)

    return RealtimeSubscription { [weak callbackManager, logger] in
      logger?.debug("Removing presence callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }
  }

  /// Registers a closure that is called for every Postgres change event on the specified table.
  ///
  /// Use ``AnyAction`` to receive insert, update, and delete changes in one callback.
  /// Register this callback before calling ``subscribeWithError()``.
  ///
  /// ```swift
  /// let subscription = channel.onPostgresChange(AnyAction.self, schema: "public", table: "messages") { action in
  ///   switch action {
  ///   case .insert(let insert): print(insert.record)
  ///   case .update(let update): print(update.record)
  ///   case .delete(let delete): print(delete.oldRecord)
  ///   }
  /// }
  /// ```
  ///
  /// > Note: Use ``postgresChange(_:schema:table:filter:)`` if you prefer async iteration over closures.
  ///
  /// - Parameters:
  ///   - type: Pass `AnyAction.self` to match all change types.
  ///   - schema: The database schema to listen on. Defaults to `"public"`.
  ///   - table: The table name to filter changes, or `nil` to listen to all tables in the schema.
  ///   - filter: A ``RealtimePostgresFilter`` restricting which rows are received.
  ///   - select: Restricts the change payload to a subset of columns. Requires an explicit `schema` and `table`.
  ///   - callback: A `@Sendable` closure receiving an ``AnyAction`` for each change.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  public func onPostgresChange(
    _: AnyAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil,
    callback: @escaping @Sendable (AnyAction) -> Void
  ) -> RealtimeSubscription {
    _onPostgresChange(
      event: .all,
      schema: schema,
      table: table,
      filter: filter?.value,
      select: select
    ) {
      callback($0)
    }
  }

  /// Listen for postgres changes in a channel.
  @_disfavoredOverload
  public func onPostgresChange(
    _: AnyAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil,
    select: [String]? = nil,
    callback: @escaping @Sendable (AnyAction) -> Void
  ) -> RealtimeSubscription {
    _onPostgresChange(
      event: .all,
      schema: schema,
      table: table,
      filter: filter,
      select: select
    ) {
      callback($0)
    }
  }

  /// Registers a closure that is called for every `INSERT` change on the specified table.
  ///
  /// Register this callback before calling ``subscribeWithError()``.
  ///
  /// ```swift
  /// let subscription = channel.onPostgresChange(InsertAction.self, schema: "public", table: "messages") { insert in
  ///   print(insert.record)
  /// }
  /// ```
  ///
  /// > Note: Use ``postgresChange(_:schema:table:filter:)`` if you prefer async iteration over closures.
  ///
  /// - Parameters:
  ///   - type: Pass `InsertAction.self`.
  ///   - schema: The database schema to listen on. Defaults to `"public"`.
  ///   - table: The table name to filter changes, or `nil` to listen to all tables in the schema.
  ///   - filter: A ``RealtimePostgresFilter`` restricting which rows are received.
  ///   - select: Restricts the change payload to a subset of columns. Requires an explicit `schema` and `table`.
  ///   - callback: A `@Sendable` closure receiving an ``InsertAction`` for each insert.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  public func onPostgresChange(
    _: InsertAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil,
    callback: @escaping @Sendable (InsertAction) -> Void
  ) -> RealtimeSubscription {
    _onPostgresChange(
      event: .insert,
      schema: schema,
      table: table,
      filter: filter?.value,
      select: select
    ) {
      guard case .insert(let action) = $0 else { return }
      callback(action)
    }
  }

  /// Listen for postgres changes in a channel.
  @_disfavoredOverload
  public func onPostgresChange(
    _: InsertAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil,
    select: [String]? = nil,
    callback: @escaping @Sendable (InsertAction) -> Void
  ) -> RealtimeSubscription {
    _onPostgresChange(
      event: .insert,
      schema: schema,
      table: table,
      filter: filter,
      select: select
    ) {
      guard case .insert(let action) = $0 else { return }
      callback(action)
    }
  }

  /// Registers a closure that is called for every `UPDATE` change on the specified table.
  ///
  /// Register this callback before calling ``subscribeWithError()``.
  ///
  /// ```swift
  /// let subscription = channel.onPostgresChange(UpdateAction.self, schema: "public", table: "messages") { update in
  ///   print(update.record, update.oldRecord)
  /// }
  /// ```
  ///
  /// > Note: Use ``postgresChange(_:schema:table:filter:)`` if you prefer async iteration over closures.
  ///
  /// - Parameters:
  ///   - type: Pass `UpdateAction.self`.
  ///   - schema: The database schema to listen on. Defaults to `"public"`.
  ///   - table: The table name to filter changes, or `nil` to listen to all tables in the schema.
  ///   - filter: A ``RealtimePostgresFilter`` restricting which rows are received.
  ///   - select: Restricts the change payload to a subset of columns. Requires an explicit `schema` and `table`.
  ///   - callback: A `@Sendable` closure receiving an ``UpdateAction`` for each update.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  public func onPostgresChange(
    _: UpdateAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil,
    callback: @escaping @Sendable (UpdateAction) -> Void
  ) -> RealtimeSubscription {
    _onPostgresChange(
      event: .update,
      schema: schema,
      table: table,
      filter: filter?.value,
      select: select
    ) {
      guard case .update(let action) = $0 else { return }
      callback(action)
    }
  }

  /// Listen for postgres changes in a channel.
  @_disfavoredOverload
  public func onPostgresChange(
    _: UpdateAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil,
    select: [String]? = nil,
    callback: @escaping @Sendable (UpdateAction) -> Void
  ) -> RealtimeSubscription {
    _onPostgresChange(
      event: .update,
      schema: schema,
      table: table,
      filter: filter,
      select: select
    ) {
      guard case .update(let action) = $0 else { return }
      callback(action)
    }
  }

  /// Registers a closure that is called for every `DELETE` change on the specified table.
  ///
  /// Register this callback before calling ``subscribeWithError()``.
  ///
  /// ```swift
  /// let subscription = channel.onPostgresChange(DeleteAction.self, schema: "public", table: "messages") { delete in
  ///   print(delete.oldRecord)
  /// }
  /// ```
  ///
  /// > Note: Use ``postgresChange(_:schema:table:filter:)`` if you prefer async iteration over closures.
  ///
  /// - Parameters:
  ///   - type: Pass `DeleteAction.self`.
  ///   - schema: The database schema to listen on. Defaults to `"public"`.
  ///   - table: The table name to filter changes, or `nil` to listen to all tables in the schema.
  ///   - filter: A ``RealtimePostgresFilter`` restricting which rows are received.
  ///   - select: Restricts the change payload to a subset of columns. Requires an explicit `schema` and `table`.
  ///   - callback: A `@Sendable` closure receiving a ``DeleteAction`` for each deletion.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  public func onPostgresChange(
    _: DeleteAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: RealtimePostgresFilter? = nil,
    select: [String]? = nil,
    callback: @escaping @Sendable (DeleteAction) -> Void
  ) -> RealtimeSubscription {
    _onPostgresChange(
      event: .delete,
      schema: schema,
      table: table,
      filter: filter?.value,
      select: select
    ) {
      guard case .delete(let action) = $0 else { return }
      callback(action)
    }
  }

  /// Listen for postgres changes in a channel.
  @_disfavoredOverload
  public func onPostgresChange(
    _: DeleteAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil,
    select: [String]? = nil,
    callback: @escaping @Sendable (DeleteAction) -> Void
  ) -> RealtimeSubscription {
    _onPostgresChange(
      event: .delete,
      schema: schema,
      table: table,
      filter: filter,
      select: select
    ) {
      guard case .delete(let action) = $0 else { return }
      callback(action)
    }
  }

  func _onPostgresChange(
    event: PostgresChangeEvent,
    schema: String,
    table: String?,
    filter: String?,
    select: [String]? = nil,
    callback: @escaping @Sendable (AnyAction) -> Void
  ) -> RealtimeSubscription {
    guard status != .subscribed && status != .subscribing else {
      // See the comment on `broadcast(event:message:)` for why this is gated on `isTesting`.
      if !isTesting {
        reportIssue(
          """
          Cannot add "postgres_changes" callbacks for "\(topic)" after `subscribe()`.
          Please add all your postgres change callbacks before subscribing to the channel.
          """
        )
      }
      return RealtimeSubscription {}
    }

    let config = PostgresJoinConfig(
      event: event,
      schema: schema,
      table: table,
      filter: filter,
      select: select
    )

    // Synchronous append — the buffer lives on the channel, not the actor,
    // so this write cannot be reordered against a subsequent `subscribe()`
    // call (previously a fire-and-forget `Task` could lose this race,
    // causing `phx_join` to be sent with an empty `postgres_changes` set).
    clientChanges.withValue { $0.append(config) }

    let id = callbackManager.addPostgresCallback(filter: config, callback: callback)
    return RealtimeSubscription { [weak callbackManager, logger] in
      logger?.debug("Removing postgres callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }
  }

  /// Registers a closure that is called when a JSON broadcast message arrives for the given event.
  ///
  /// ```swift
  /// let subscription = channel.onBroadcast(event: "cursor") { payload in
  ///   print(payload)
  /// }
  /// ```
  ///
  /// > Note: Use ``broadcastStream(event:)`` if you prefer async iteration over closures.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name to listen for.
  ///   - callback: A `@Sendable` closure receiving the ``JSONObject`` payload.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  public func onBroadcast(
    event: String,
    callback: @escaping @Sendable (JSONObject) -> Void
  ) -> RealtimeSubscription {
    let id = callbackManager.addBroadcastCallback(event: event, callback: callback)
    return RealtimeSubscription { [weak callbackManager, logger] in
      logger?.debug("Removing broadcast callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }
  }

  /// Registers a closure that is called when a binary broadcast message arrives for the given event.
  ///
  /// Use this when you expect binary (non-JSON) broadcast payloads sent via
  /// ``broadcast(event:data:)``. Requires protocol ``RealtimeProtocolVersion/v2``.
  ///
  /// ```swift
  /// let subscription = channel.onBroadcastData(event: "frame") { data in
  ///   process(data)
  /// }
  /// ```
  ///
  /// > Note: Use ``broadcastDataStream(event:)`` if you prefer async iteration over closures.
  ///
  /// - Parameters:
  ///   - event: The broadcast event name to listen for.
  ///   - callback: A `@Sendable` closure receiving the raw `Data` payload.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  public func onBroadcastData(
    event: String,
    callback: @escaping @Sendable (Data) -> Void
  ) -> RealtimeSubscription {
    let id = callbackManager.addBroadcastDataCallback(event: event, callback: callback)
    return RealtimeSubscription { [weak callbackManager, logger] in
      logger?.debug("Removing broadcast data callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }
  }

  /// Registers a closure that is called when a `system` event is received, providing the full message.
  ///
  /// System events are emitted by the server to convey channel-level status information.
  ///
  /// ```swift
  /// let subscription = channel.onSystem { message in
  ///   print(message.payload)
  /// }
  /// ```
  ///
  /// > Note: Use ``system()`` if you prefer async iteration over closures.
  ///
  /// - Parameter callback: A `@Sendable` closure receiving the ``RealtimeMessageV2``.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  public func onSystem(
    callback: @escaping @Sendable (RealtimeMessageV2) -> Void
  ) -> RealtimeSubscription {
    let id = callbackManager.addSystemCallback(callback: callback)
    return RealtimeSubscription { [weak callbackManager, logger] in
      logger?.debug("Removing system callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }
  }

  /// Registers a no-argument closure that is called when a `system` event is received.
  ///
  /// Use this overload when you only need to know that a system event occurred, not its contents.
  ///
  /// - Parameter callback: A `@Sendable` closure called on each system event.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  public func onSystem(
    callback: @escaping @Sendable () -> Void
  ) -> RealtimeSubscription {
    self.onSystem { _ in callback() }
  }

  @MainActor
  @discardableResult
  func push(_ event: String, ref: String? = nil, payload: JSONObject = [:]) async -> PushStatus {
    let joinRef = await stateManager.joinRef
    let message = RealtimeMessageV2(
      joinRef: joinRef,
      ref: ref ?? socket.makeRef(),
      topic: self.topic,
      event: event,
      payload: payload
    )

    let push = PushV2(channel: self, message: message)
    if let ref = message.ref {
      // Registering under `ref` must be guarded by the `joinRef` snapshot:
      // if `didReceiveClose` ran on the actor between our `joinRef` read
      // above and this call, the message we'd be sending is from a prior
      // subscription cycle (the server will reject it) and keeping the
      // push in the dictionary would orphan it — nothing would clear it
      // again. `storePushIfJoinRefMatches` makes this pair atomic.
      let stored = await stateManager.storePushIfJoinRefMatches(
        push, ref: ref, joinRef: joinRef
      )
      guard stored else {
        logger?.debug(
          "Abandoning stale push for '\(topic)': channel closed between joinRef snapshot and store"
        )
        return .error
      }
    }

    return await push.send()
  }

  @MainActor
  private func didReceiveReply(ref: String, status: String) async {
    let push = await stateManager.removePush(ref: ref)
    push?.didReceive(status: PushStatus(rawValue: status) ?? .ok)
  }
}

/// Holds a weak reference so the closures we hand to ``ChannelStateManager``
/// at init don't pin the channel alive. Assignment happens exactly once in
/// ``RealtimeChannelV2.init``, before the reference escapes the initializer.
private final class WeakChannelRef: @unchecked Sendable {
  weak var value: RealtimeChannelV2?
}
