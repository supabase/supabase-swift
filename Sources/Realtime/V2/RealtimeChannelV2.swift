//
//  RealtimeChannelV2.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import ConcurrencyExtras
import Foundation
import Helpers

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

struct Socket: Sendable {
  var broadcastURL: @Sendable () -> URL
  var status: @Sendable () -> RealtimeClientStatus
  var options: @Sendable () -> RealtimeClientOptions
  var accessToken: @Sendable () -> String?
  var apiKey: @Sendable () -> String?
  var makeRef: @Sendable () -> Int

  var connect: @Sendable () async -> Void
  var addChannel: @Sendable (_ channel: RealtimeChannelV2) -> Void
  var removeChannel: @Sendable (_ channel: RealtimeChannelV2) async -> Void
  var push: @Sendable (_ message: RealtimeMessageV2) async -> Void
  var httpSend: @Sendable (_ request: HTTPRequest) async throws -> HTTPResponse
}

extension Socket {
  init(client: RealtimeClientV2) {
    self.init(
      broadcastURL: { [weak client] in client?.broadcastURL ?? URL(string: "http://localhost")! },
      status: { [weak client] in client?.status ?? .disconnected },
      options: { [weak client] in client?.options ?? .init() },
      accessToken: { [weak client] in client?.mutableState.accessToken },
      apiKey: { [weak client] in client?.apikey },
      makeRef: { [weak client] in client?.makeRef() ?? 0 },
      connect: { [weak client] in await client?.connect() },
      addChannel: { [weak client] in client?.addChannel($0) },
      removeChannel: { [weak client] in await client?.removeChannel($0) },
      push: { [weak client] in await client?.push($0) },
      httpSend: { [weak client] in try await client?.http.send($0) ?? .init(data: Data(), response: HTTPURLResponse()) }
    )
  }
}

public final class RealtimeChannelV2: Sendable {
  struct MutableState {
    var clientChanges: [PostgresJoinConfig] = []
    var joinRef: String?
    var pushes: [String: PushV2] = [:]
  }

  private let mutableState = LockIsolated(MutableState())

  let topic: String
  let config: RealtimeChannelConfig
  let logger: (any SupabaseLogger)?
  let socket: Socket

  let callbackManager = CallbackManager()
  private let statusEventEmitter = EventEmitter<RealtimeChannelStatus>(initialEvent: .unsubscribed)

  public private(set) var status: RealtimeChannelStatus {
    get { statusEventEmitter.lastEvent }
    set { statusEventEmitter.emit(newValue) }
  }

  public var statusChange: AsyncStream<RealtimeChannelStatus> {
    statusEventEmitter.stream()
  }

  /// Listen for connection status changes.
  /// - Parameter listener: Closure that will be called when connection status changes.
  /// - Returns: An observation handle that can be used to stop listening.
  ///
  /// - Note: Use ``statusChange`` if you prefer to use Async/Await.
  public func onStatusChange(
    _ listener: @escaping @Sendable (RealtimeChannelStatus) -> Void
  ) -> ObservationToken {
    statusEventEmitter.attach(listener)
  }

  init(
    topic: String,
    config: RealtimeChannelConfig,
    socket: Socket,
    logger: (any SupabaseLogger)?
  ) {
    self.topic = topic
    self.config = config
    self.logger = logger
    self.socket = socket
  }

  deinit {
    callbackManager.reset()
  }

  /// Subscribes to the channel
  public func subscribe() async {
    if socket.status() != .connected {
      if socket.options().connectOnSubscribe != true {
        fatalError(
          "You can't subscribe to a channel while the realtime client is not connected. Did you forget to call `realtime.connect()`?"
        )
      }
      await socket.connect()
    }

    guard status != .subscribed else {
      logger?.warning("Channel \(topic) is already subscribed")
      return
    }

    socket.addChannel(self)

    status = .subscribing
    logger?.debug("Subscribing to channel \(topic)")

    let joinConfig = RealtimeJoinConfig(
      broadcast: config.broadcast,
      presence: config.presence,
      postgresChanges: mutableState.clientChanges,
      isPrivate: config.isPrivate
    )

    let payload = RealtimeJoinPayload(
      config: joinConfig,
      accessToken: socket.accessToken()
    )

    let joinRef = socket.makeRef().description
    mutableState.withValue { $0.joinRef = joinRef }

    logger?.debug("Subscribing to channel with body: \(joinConfig)")

    await push(
      RealtimeMessageV2(
        joinRef: joinRef,
        ref: joinRef,
        topic: topic,
        event: ChannelEvent.join,
        payload: try! JSONObject(payload)
      )
    )

    do {
      try await withTimeout(interval: socket.options().timeoutInterval) { [self] in
        _ = await statusChange.first { @Sendable in $0 == .subscribed }
      }
    } catch {
      if error is TimeoutError {
        logger?.debug("Subscribe timed out.")
        await subscribe()
      } else {
        logger?.error("Subscribe failed: \(error)")
      }
    }
  }

  public func unsubscribe() async {
    status = .unsubscribing
    logger?.debug("Unsubscribing from channel \(topic)")

    await push(
      RealtimeMessageV2(
        joinRef: mutableState.joinRef,
        ref: socket.makeRef().description,
        topic: topic,
        event: ChannelEvent.leave,
        payload: [:]
      )
    )
  }

  public func updateAuth(jwt: String) async {
    logger?.debug("Updating auth token for channel \(topic)")
    await push(
      RealtimeMessageV2(
        joinRef: mutableState.joinRef,
        ref: socket.makeRef().description,
        topic: topic,
        event: ChannelEvent.accessToken,
        payload: ["access_token": .string(jwt)]
      )
    )
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
  public func broadcast(event: String, message: JSONObject) async {
    if status != .subscribed {
      struct Message: Encodable {
        let topic: String
        let event: String
        let payload: JSONObject
        let `private`: Bool
      }

      var headers = HTTPHeaders(["content-type": "application/json"])
      if let apiKey = socket.apiKey() {
        headers["apikey"] = apiKey
      }
      if let accessToken = socket.accessToken() {
        headers["authorization"] = "Bearer \(accessToken)"
      }

      let task = Task { [headers] in
        _ = try? await socket.httpSend(
          HTTPRequest(
            url: socket.broadcastURL(),
            method: .post,
            headers: headers,
            body: JSONEncoder().encode(
              [
                "messages": [
                  Message(
                    topic: topic,
                    event: event,
                    payload: message,
                    private: config.isPrivate
                  ),
                ],
              ]
            )
          )
        )
      }

      if config.broadcast.acknowledgeBroadcasts {
        try? await withTimeout(interval: socket.options().timeoutInterval) {
          await task.value
        }
      }
    } else {
      await push(
        RealtimeMessageV2(
          joinRef: mutableState.joinRef,
          ref: socket.makeRef().description,
          topic: topic,
          event: ChannelEvent.broadcast,
          payload: [
            "type": "broadcast",
            "event": .string(event),
            "payload": .object(message),
          ]
        )
      )
    }
  }

  public func track(_ state: some Codable) async throws {
    try await track(state: JSONObject(state))
  }

  public func track(state: JSONObject) async {
    assert(
      status == .subscribed,
      "You can only track your presence after subscribing to the channel. Did you forget to call `channel.subscribe()`?"
    )

    await push(
      RealtimeMessageV2(
        joinRef: mutableState.joinRef,
        ref: socket.makeRef().description,
        topic: topic,
        event: ChannelEvent.presence,
        payload: [
          "type": "presence",
          "event": "track",
          "payload": .object(state),
        ]
      )
    )
  }

  public func untrack() async {
    await push(
      RealtimeMessageV2(
        joinRef: mutableState.joinRef,
        ref: socket.makeRef().description,
        topic: topic,
        event: ChannelEvent.presence,
        payload: [
          "type": "presence",
          "event": "untrack",
        ]
      )
    )
  }

  func onMessage(_ message: RealtimeMessageV2) async {
    do {
      guard let eventType = message.eventType else {
        logger?.debug("Received message without event type: \(message)")
        return
      }

      switch eventType {
      case .tokenExpired:
        logger?.debug(
          "Received token expired event. This should not happen, please report this warning."
        )

      case .system:
        logger?.debug("Subscribed to channel \(message.topic)")
        status = .subscribed

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

          if self.status != .subscribed {
            self.status = .subscribed
            logger?.debug("Subscribed to channel \(message.topic)")
          }
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
        await socket.removeChannel(self)
        logger?.debug("Unsubscribed from channel \(message.topic)")
        status = .unsubscribed

      case .error:
        logger?.debug(
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

  /// Listen for clients joining / leaving the channel using presences.
  public func onPresenceChange(
    _ callback: @escaping @Sendable (any PresenceAction) -> Void
  ) -> RealtimeSubscription {
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
      guard case let .insert(action) = $0 else { return }
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
      guard case let .update(action) = $0 else { return }
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
      guard case let .delete(action) = $0 else { return }
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
    precondition(
      status != .subscribed,
      "You cannot call postgresChange after joining the channel"
    )

    let config = PostgresJoinConfig(
      event: event,
      schema: schema,
      table: table,
      filter: filter
    )

    mutableState.withValue {
      $0.clientChanges.append(config)
    }

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

  @discardableResult
  private func push(_ message: RealtimeMessageV2) async -> PushStatus {
    let push = PushV2(channel: self, message: message)
    if let ref = message.ref {
      mutableState.withValue {
        $0.pushes[ref] = push
      }
    }
    return await push.send()
  }

  private func didReceiveReply(ref: String, status: String) async {
    let push = mutableState.withValue {
      $0.pushes.removeValue(forKey: ref)
    }
    await push?.didReceive(status: PushStatus(rawValue: status) ?? .ok)
  }
}
