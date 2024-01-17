//
//  Channel.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

@_spi(Internal) import _Helpers
import ConcurrencyExtras
import Foundation

public struct RealtimeChannelConfig: Sendable {
  public var broadcast: BroadcastJoinConfig
  public var presence: PresenceJoinConfig
}

public actor RealtimeChannelV2 {
  public enum Status: Sendable {
    case unsubscribed
    case subscribing
    case subscribed
    case unsubscribing
  }

  weak var socket: RealtimeClientV2? {
    didSet {
      assert(oldValue == nil, "socket should not be modified once set")
    }
  }

  let topic: String
  let config: RealtimeChannelConfig
  let logger: SupabaseLogger?

  private let callbackManager = CallbackManager()
  let statusStreamManager = AsyncStreamManager<Status>()

  private var clientChanges: [PostgresJoinConfig] = []
  private var joinRef: String?
  private var pushes: [String: _Push] = [:]

  public var status: AsyncStream<Status> {
    statusStreamManager.makeStream()
  }

  init(
    topic: String,
    config: RealtimeChannelConfig,
    socket: RealtimeClientV2,
    logger: SupabaseLogger?
  ) {
    self.socket = socket
    self.topic = topic
    self.config = config
    self.logger = logger
  }

  deinit {
    callbackManager.reset()
  }

  /// Subscribes to the channel
  /// - Parameter blockUntilSubscribed: if true, the method will block the current Task until the
  /// ``status-swift.property`` is ``Status-swift.enum/subscribed``.
  public func subscribe(blockUntilSubscribed: Bool = false) async {
    if socket?.statusStreamManager.value != .connected {
      if socket?.config.connectOnSubscribe != true {
        fatalError(
          "You can't subscribe to a channel while the realtime client is not connected. Did you forget to call `realtime.connect()`?"
        )
      }
      await socket?.connect()
    }

    await socket?.addChannel(self)

    statusStreamManager.yield(.subscribing)
    logger?.debug("subscribing to channel \(topic)")

    let accessToken = await socket?.accessToken

    let postgresChanges = clientChanges

    let joinConfig = RealtimeJoinConfig(
      broadcast: config.broadcast,
      presence: config.presence,
      postgresChanges: postgresChanges,
      accessToken: accessToken
    )

    joinRef = await socket?.makeRef().description

    logger?.debug("subscribing to channel with body: \(joinConfig)")

    await push(
      RealtimeMessageV2(
        joinRef: joinRef,
        ref: joinRef,
        topic: topic,
        event: ChannelEvent.join,
        payload: (try? JSONObject(RealtimeJoinPayload(config: joinConfig))) ?? [:]
      )
    )

    if blockUntilSubscribed {
      _ = await status.first { $0 == .subscribed }
    }
  }

  public func unsubscribe() async {
    statusStreamManager.yield(.unsubscribing)
    logger?.debug("unsubscribing from channel \(topic)")

    await push(
      RealtimeMessageV2(
        joinRef: joinRef,
        ref: socket?.makeRef().description,
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
        joinRef: joinRef,
        ref: socket?.makeRef().description,
        topic: topic,
        event: ChannelEvent.accessToken,
        payload: ["access_token": .string(jwt)]
      )
    )
  }

  public func broadcast(event: String, message: [String: AnyJSON]) async {
    assert(
      statusStreamManager.value == .subscribed,
      "You can only broadcast after subscribing to the channel. Did you forget to call `channel.subscribe()`?"
    )

    await push(
      RealtimeMessageV2(
        joinRef: joinRef,
        ref: socket?.makeRef().description,
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

  public func track(_ state: some Codable) async throws {
    try await track(state: JSONObject(state))
  }

  public func track(state: JSONObject) async {
    assert(
      statusStreamManager.value == .subscribed,
      "You can only track your presence after subscribing to the channel. Did you forget to call `channel.subscribe()`?"
    )

    await push(
      RealtimeMessageV2(
        joinRef: joinRef,
        ref: socket?.makeRef().description,
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
        joinRef: joinRef,
        ref: socket?.makeRef().description,
        topic: topic,
        event: ChannelEvent.presence,
        payload: [
          "type": "presence",
          "event": "untrack",
        ]
      )
    )
  }

  func onMessage(_ message: RealtimeMessageV2) {
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
        statusStreamManager.yield(.subscribed)

      case .reply:
        guard
          let ref = message.ref,
          let status = message.payload["status"]?.stringValue
        else {
          throw RealtimeError("Received a reply with unexpected payload: \(message)")
        }

        didReceiveReply(ref: ref, status: status)

        if message.payload["response"]?.objectValue?.keys
          .contains(ChannelEvent.postgresChanges) == true
        {
          let serverPostgresChanges = try message.payload["response"]?
            .objectValue?["postgres_changes"]?
            .decode([PostgresJoinConfig].self)

          callbackManager.setServerChanges(changes: serverPostgresChanges ?? [])

          if statusStreamManager.value != .subscribed {
            statusStreamManager.yield(.subscribed)
            logger?.debug("Subscribed to channel \(message.topic)")
          }
        }

      case .postgresChanges:
        guard let data = message.payload["data"] else {
          logger?.debug("Expected \"data\" key in message payload.")
          return
        }

        let ids = message.payload["ids"]?.arrayValue?.compactMap(\.intValue) ?? []

        let postgresActions = try data.decode(PostgresActionData.self)

        let action: AnyAction = switch postgresActions.type {
        case "UPDATE":
          .update(
            UpdateAction(
              columns: postgresActions.columns,
              commitTimestamp: postgresActions.commitTimestamp,
              record: postgresActions.record ?? [:],
              oldRecord: postgresActions.oldRecord ?? [:],
              rawMessage: message
            )
          )

        case "DELETE":
          .delete(
            DeleteAction(
              columns: postgresActions.columns,
              commitTimestamp: postgresActions.commitTimestamp,
              oldRecord: postgresActions.oldRecord ?? [:],
              rawMessage: message
            )
          )

        case "INSERT":
          .insert(
            InsertAction(
              columns: postgresActions.columns,
              commitTimestamp: postgresActions.commitTimestamp,
              record: postgresActions.record ?? [:],
              rawMessage: message
            )
          )

        case "SELECT":
          .select(
            SelectAction(
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
        Task { [weak self] in
          guard let self else { return }

          await socket?.removeChannel(self)
          logger?.debug("Unsubscribed from channel \(message.topic)")
        }

      case .error:
        logger?.debug(
          "Received an error in channel \(message.topic). That could be as a result of an invalid access token"
        )

      case .presenceDiff:
        let joins = try message.payload["joins"]?.decode([String: _Presence].self) ?? [:]
        let leaves = try message.payload["leaves"]?.decode([String: _Presence].self) ?? [:]
        callbackManager.triggerPresenceDiffs(joins: joins, leaves: leaves, rawMessage: message)

      case .presenceState:
        let joins = try message.payload.decode([String: _Presence].self)
        callbackManager.triggerPresenceDiffs(joins: joins, leaves: [:], rawMessage: message)
      }
    } catch {
      logger?.debug("Failed: \(error)")
    }
  }

  /// Listen for clients joining / leaving the channel using presences.
  public func presenceChange() -> AsyncStream<PresenceAction> {
    let (stream, continuation) = AsyncStream<PresenceAction>.makeStream()

    let id = callbackManager.addPresenceCallback {
      continuation.yield($0)
    }

    let logger = logger

    continuation.onTermination = { [weak callbackManager] _ in
      logger?.debug("Removing presence callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }

    return stream
  }

  /// Listen for postgres changes in a channel.
  public func postgresChange(
    _: InsertAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil
  ) -> AsyncStream<InsertAction> {
    postgresChange(event: .insert, schema: schema, table: table, filter: filter)
      .compactMap { $0.wrappedAction as? InsertAction }
      .eraseToStream()
  }

  /// Listen for postgres changes in a channel.
  public func postgresChange(
    _: UpdateAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil
  ) -> AsyncStream<UpdateAction> {
    postgresChange(event: .update, schema: schema, table: table, filter: filter)
      .compactMap { $0.wrappedAction as? UpdateAction }
      .eraseToStream()
  }

  /// Listen for postgres changes in a channel.
  public func postgresChange(
    _: DeleteAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil
  ) -> AsyncStream<DeleteAction> {
    postgresChange(event: .delete, schema: schema, table: table, filter: filter)
      .compactMap { $0.wrappedAction as? DeleteAction }
      .eraseToStream()
  }

  /// Listen for postgres changes in a channel.
  public func postgresChange(
    _: SelectAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil
  ) -> AsyncStream<SelectAction> {
    postgresChange(event: .select, schema: schema, table: table, filter: filter)
      .compactMap { $0.wrappedAction as? SelectAction }
      .eraseToStream()
  }

  /// Listen for postgres changes in a channel.
  public func postgresChange(
    _: AnyAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil
  ) -> AsyncStream<AnyAction> {
    postgresChange(event: .all, schema: schema, table: table, filter: filter)
  }

  private func postgresChange(
    event: PostgresChangeEvent,
    schema: String,
    table: String?,
    filter: String?
  ) -> AsyncStream<AnyAction> {
    precondition(
      statusStreamManager.value != .subscribed,
      "You cannot call postgresChange after joining the channel"
    )

    let (stream, continuation) = AsyncStream<AnyAction>.makeStream()

    let config = PostgresJoinConfig(
      event: event,
      schema: schema,
      table: table,
      filter: filter
    )

    clientChanges.append(config)

    let id = callbackManager.addPostgresCallback(filter: config) { action in
      continuation.yield(action)
    }

    let logger = logger

    continuation.onTermination = { [weak callbackManager] _ in
      logger?.debug("Removing postgres callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }

    return stream
  }

  /// Listen for broadcast messages sent by other clients within the same channel under a specific
  /// `event`.
  public func broadcast(event: String) -> AsyncStream<JSONObject> {
    let (stream, continuation) = AsyncStream<JSONObject>.makeStream()

    let id = callbackManager.addBroadcastCallback(event: event) {
      continuation.yield($0)
    }

    let logger = logger

    continuation.onTermination = { [weak callbackManager] _ in
      logger?.debug("Removing broadcast callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }

    return stream
  }

  @discardableResult
  private func push(_ message: RealtimeMessageV2) async -> PushStatus {
    let push = _Push(channel: self, message: message)
    if let ref = message.ref {
      pushes[ref] = push
    }
    return await push.send()
  }

  private func didReceiveReply(ref: String, status: String) {
    Task {
      let push = pushes.removeValue(forKey: ref)
      await push?.didReceive(status: PushStatus(rawValue: status) ?? .ok)
    }
  }
}
