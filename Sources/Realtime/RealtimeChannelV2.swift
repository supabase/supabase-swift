import ConcurrencyExtras
import Foundation
import HTTPTypes
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

public struct RealtimeChannelConfig: Sendable {
  public var broadcast: BroadcastJoinConfig
  public var presence: PresenceJoinConfig
  public var isPrivate: Bool
}

protocol RealtimeChannelProtocol: AnyObject, Sendable {
  @MainActor var config: RealtimeChannelConfig { get }
  var topic: String { get }
  var logger: (any SupabaseLogger)? { get }

  var socket: any RealtimeClientProtocol { get }
}

public final class RealtimeChannelV2: Sendable, RealtimeChannelProtocol {
  public let topic: String

  @MainActor public private(set) var config: RealtimeChannelConfig

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

  private let statusSubject = AsyncValueSubject<RealtimeChannelStatus>(.unsubscribed)

  public private(set) var status: RealtimeChannelStatus {
    get { statusSubject.value }
    set { statusSubject.yield(newValue) }
  }

  public var statusChange: AsyncStream<RealtimeChannelStatus> {
    statusSubject.values
  }

  /// Listen for connection status changes.
  /// - Parameter listener: Closure that will be called when connection status changes.
  /// - Returns: An observation handle that can be used to stop listening.
  ///
  /// - Note: Use ``statusChange`` if you prefer to use Async/Await.
  public func onStatusChange(
    _ listener: @escaping @Sendable (RealtimeChannelStatus) -> Void
  ) -> RealtimeSubscription {
    let task = statusSubject.onChange { listener($0) }
    return RealtimeSubscription { task.cancel() }
  }

  init(
    topic: String,
    config: RealtimeChannelConfig,
    socket: any RealtimeClientProtocol,
    logger: (any SupabaseLogger)?
  ) {
    self.topic = topic
    self.config = config
    self.logger = logger
    self.socket = socket

    let weakSelfRef = WeakChannelRef()
    let statusSubject = self.statusSubject
    let clientChanges = self.clientChanges
    self.stateManager = ChannelStateManager(
      topic: topic,
      logger: logger,
      maxRetryAttempts: socket.options.maxRetryAttempts,
      timeoutInterval: socket.options.timeoutInterval,
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
      getClientChanges: { clientChanges.value },
      joinOperation: { [weakSelfRef] ref, changes in
        guard let channel = weakSelfRef.value else { return }
        await channel.performJoin(ref: ref, clientChanges: changes)
      },
      leaveOperation: { [weakSelfRef] in
        guard let channel = weakSelfRef.value else { return }
        await channel.push(ChannelEvent.leave)
      },
      stateDidChange: { state in
        // Forward every state-machine transition to the public status
        // subject synchronously. Running this on the actor avoids the
        // async observer-Task delay, so reads of ``status`` right after
        // ``subscribe()`` returns see the latest value.
        statusSubject.yield(Self.mapState(state))
      }
    )

    weakSelfRef.value = self
  }

  deinit {
    callbackManager.reset()
  }

  private static func mapState(_ state: ChannelStateManager.State) -> RealtimeChannelStatus {
    switch state {
    case .unsubscribed: .unsubscribed
    case .subscribing: .subscribing
    case .subscribed: .subscribed
    case .unsubscribing: .unsubscribing
    }
  }

  /// Subscribes to the channel.
  public func subscribeWithError() async throws {
    logger?.debug("Subscribe requested for channel '\(topic)'")
    try await stateManager.subscribe()
  }

  /// Subscribes to the channel.
  @available(*, deprecated, message: "Use `subscribeWithError` instead")
  @MainActor
  public func subscribe() async {
    try? await subscribeWithError()
  }

  public func unsubscribe() async {
    logger?.debug("Unsubscribe requested for channel '\(topic)'")
    await stateManager.unsubscribe()
  }

  /// Build the `phx_join` payload from the current config and push it.
  /// Invoked by ``ChannelStateManager`` via the ``ChannelStateManager/JoinOperation``
  /// closure at the moment the state machine is ready to join.
  @MainActor
  private func performJoin(ref: String, clientChanges: [PostgresJoinConfig]) async {
    logger?.debug("Sending phx_join for channel '\(topic)' (ref: \(ref))")

    config.presence.enabled = callbackManager.callbacks.contains(where: { $0.isPresence })

    let joinConfig = RealtimeJoinConfig(
      broadcast: config.broadcast,
      presence: config.presence,
      postgresChanges: clientChanges,
      isPrivate: config.isPrivate
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

  /// Sends a broadcast message explicitly via REST API.
  ///
  /// This method always uses the REST API endpoint regardless of WebSocket connection state.
  /// Useful when you want to guarantee REST delivery or when gradually migrating from implicit REST fallback.
  ///
  /// - Parameters:
  ///   - event: The name of the broadcast event.
  ///   - message: Message payload (required).
  ///   - timeout: Optional timeout interval. If not specified, uses the socket's default timeout.
  /// - Returns: `true` if the message was accepted (HTTP 202), otherwise throws an error.
  /// - Throws: An error if the access token is missing, payload is missing, or the request fails.
  public func httpSend(
    event: String,
    message: some Codable,
    timeout: TimeInterval? = nil
  ) async throws {
    try await httpSend(event: event, message: JSONObject(message), timeout: timeout)
  }

  /// Sends a broadcast message explicitly via REST API.
  ///
  /// This method always uses the REST API endpoint regardless of WebSocket connection state.
  /// Useful when you want to guarantee REST delivery or when gradually migrating from implicit REST fallback.
  ///
  /// - Parameters:
  ///   - event: The name of the broadcast event.
  ///   - message: Message payload as a `JSONObject` (required).
  ///   - timeout: Optional timeout interval. If not specified, uses the socket's default timeout.
  /// - Returns: `true` if the message was accepted (HTTP 202), otherwise throws an error.
  /// - Throws: An error if the access token is missing, payload is missing, or the request fails.
  public func httpSend(
    event: String,
    message: JSONObject,
    timeout: TimeInterval? = nil
  ) async throws {
    guard let accessToken = await socket._getAccessToken() else {
      throw RealtimeError("Access token is required for httpSend()")
    }

    var headers: HTTPFields = [.contentType: "application/json"]
    if let apiKey = socket.options.apikey {
      headers[.apiKey] = apiKey
    }
    headers[.authorization] = "Bearer \(accessToken)"

    let body = try await JSONEncoder.supabase().encode(
      BroadcastMessagePayload(
        messages: [
          BroadcastMessagePayload.Message(
            topic: topic,
            event: event,
            payload: message,
            private: config.isPrivate
          )
        ]
      )
    )

    let request = HTTPRequest(
      url: socket.broadcastURL,
      method: .post,
      headers: headers,
      body: body
    )

    let response = try await withTimeout(interval: timeout ?? socket.options.timeoutInterval) {
      [self] in
      await Result {
        try await socket.http.send(request)
      }
    }.get()

    guard response.statusCode == 202 else {
      // Try to parse error message from response body
      var errorMessage = HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
      if let errorBody = try? response.decoded(as: [String: String].self) {
        errorMessage = errorBody["error"] ?? errorBody["message"] ?? errorMessage
      }
      throw RealtimeError(errorMessage)
    }
  }

  /// Send a broadcast message with `event` and a `Codable` payload.
  /// - Parameters:
  ///   - event: Broadcast message event.
  ///   - message: Message payload.
  public func broadcast(event: String, message: some Codable) async throws {
    try await broadcast(event: event, message: JSONObject(message))
  }

  /// Send a broadcast message with `event` and a raw `JSON` payload.
  /// - Parameters:
  ///   - event: Broadcast message event.
  ///   - message: Message payload.
  @MainActor
  public func broadcast(event: String, message: JSONObject) async {
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
            url: socket.broadcastURL,
            method: .post,
            headers: headers,
            body: JSONEncoder.supabase().encode(
              BroadcastMessagePayload(
                messages: [
                  BroadcastMessagePayload.Message(
                    topic: topic,
                    event: event,
                    payload: message,
                    private: config.isPrivate
                  )
                ]
              )
            )
          )
        )
      }

      if config.broadcast.acknowledgeBroadcasts {
        try? await withTimeout(interval: socket.options.timeoutInterval) {
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

  /// Send a broadcast message with `event` and a raw binary `Data` payload.
  ///
  /// Binary broadcasts require protocol version 2.0.0 (`vsn: .v2`).
  /// - Parameters:
  ///   - event: Broadcast message event.
  ///   - data: Binary data payload.
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

  /// Tracks the given state in the channel.
  /// - Parameter state: The state to be tracked, conforming to `Codable`.
  /// - Throws: An error if the tracking fails.
  public func track(_ state: some Codable) async throws {
    try await track(state: JSONObject(state))
  }

  /// Tracks the given state in the channel.
  /// - Parameter state: The state to be tracked as a `JSONObject`.
  public func track(state: JSONObject) async {
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

  /// Stops tracking the current state in the channel.
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
          throw RealtimeError("Received a reply with unexpected payload: \(message)")
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
          throw RealtimeError("Unknown event type: \(postgresActions.type)")
        }

        callbackManager.triggerPostgresChanges(ids: ids, data: action)

      case .broadcast:
        let payload = message.payload

        guard let event = payload["event"]?.stringValue else {
          throw RealtimeError("Expected 'event' key in 'payload' for broadcast event.")
        }

        callbackManager.triggerBroadcast(event: event, json: payload)

      case .close:
        socket._remove(self)
        await stateManager.didReceiveClose()

      case .error:
        logger?.error(
          "Received an error in channel \(message.topic). That could be as a result of an invalid access token"
        )

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

  /// Listen for clients joining / leaving the channel using presences.
  public func onPresenceChange(
    _ callback: @escaping @Sendable (any PresenceAction) -> Void
  ) -> RealtimeSubscription {
    guard status != .subscribed && status != .subscribing else {
      reportIssue(
        """
        Cannot add "presence" callbacks for "\(topic)" after `subscribe()`.
        Please add all your presence callbacks before subscribing to the channel.
        """
      )
      return RealtimeSubscription {}
    }

    let id = callbackManager.addPresenceCallback(callback: callback)

    return RealtimeSubscription { [weak callbackManager, logger] in
      logger?.debug("Removing presence callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }
  }

  /// Listen for postgres changes in a channel.
  public func onPostgresChange(
    _: AnyAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil,
    callback: @escaping @Sendable (AnyAction) -> Void
  ) -> RealtimeSubscription {
    _onPostgresChange(
      event: .all,
      schema: schema,
      table: table,
      filter: filter
    ) {
      callback($0)
    }
  }

  /// Listen for postgres changes in a channel.
  public func onPostgresChange(
    _: InsertAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil,
    callback: @escaping @Sendable (InsertAction) -> Void
  ) -> RealtimeSubscription {
    _onPostgresChange(
      event: .insert,
      schema: schema,
      table: table,
      filter: filter
    ) {
      guard case .insert(let action) = $0 else { return }
      callback(action)
    }
  }

  /// Listen for postgres changes in a channel.
  public func onPostgresChange(
    _: UpdateAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil,
    callback: @escaping @Sendable (UpdateAction) -> Void
  ) -> RealtimeSubscription {
    _onPostgresChange(
      event: .update,
      schema: schema,
      table: table,
      filter: filter
    ) {
      guard case .update(let action) = $0 else { return }
      callback(action)
    }
  }

  /// Listen for postgres changes in a channel.
  public func onPostgresChange(
    _: DeleteAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil,
    callback: @escaping @Sendable (DeleteAction) -> Void
  ) -> RealtimeSubscription {
    _onPostgresChange(
      event: .delete,
      schema: schema,
      table: table,
      filter: filter
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
    callback: @escaping @Sendable (AnyAction) -> Void
  ) -> RealtimeSubscription {
    guard status != .subscribed && status != .subscribing else {
      reportIssue(
        """
        Cannot add "postgres_changes" callbacks for "\(topic)" after `subscribe()`.
        Please add all your postgres change callbacks before subscribing to the channel.
        """
      )
      return RealtimeSubscription {}
    }

    let config = PostgresJoinConfig(
      event: event,
      schema: schema,
      table: table,
      filter: filter
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

  /// Listen for broadcast messages sent by other clients within the same channel under a specific `event`.
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

  /// Listen for binary broadcast messages sent by other clients within the same channel under a specific `event`.
  ///
  /// Use this when you expect binary (non-JSON) broadcast payloads.
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

  /// Listen for `system` event.
  public func onSystem(
    callback: @escaping @Sendable (RealtimeMessageV2) -> Void
  ) -> RealtimeSubscription {
    let id = callbackManager.addSystemCallback(callback: callback)
    return RealtimeSubscription { [weak callbackManager, logger] in
      logger?.debug("Removing system callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }
  }

  /// Listen for `system` event.
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
