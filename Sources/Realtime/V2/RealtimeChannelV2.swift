//
//  RealtimeChannelV2.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import _Helpers
import ConcurrencyExtras
import Foundation

public struct RealtimeChannelConfig: Sendable {
  public var broadcast: BroadcastJoinConfig
  public var presence: PresenceJoinConfig
}

public actor RealtimeChannelV2 {
  public typealias Subscription = ObservationToken

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
  let logger: (any SupabaseLogger)?

  private let callbackManager = CallbackManager()

  private let statusEventEmitter = EventEmitter<Status>(initialEvent: .unsubscribed)

  private var clientChanges: [PostgresJoinConfig] = []
  private var joinRef: String?
  private var pushes: [String: PushV2] = [:]

  public private(set) var status: Status {
    get { statusEventEmitter.lastEvent.value }
    set { statusEventEmitter.emit(newValue) }
  }

  public var statusChange: AsyncStream<Status> {
    statusEventEmitter.stream()
  }

  init(
    topic: String,
    config: RealtimeChannelConfig,
    socket: RealtimeClientV2,
    logger: (any SupabaseLogger)?
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
  public func subscribe() async {
    if await socket?.status != .connected {
      if socket?.config.connectOnSubscribe != true {
        fatalError(
          "You can't subscribe to a channel while the realtime client is not connected. Did you forget to call `realtime.connect()`?"
        )
      }
      await socket?.connect()
    }

    await socket?.addChannel(self)

    status = .subscribing
    logger?.debug("subscribing to channel \(topic)")

    let joinConfig = RealtimeJoinConfig(
      broadcast: config.broadcast,
      presence: config.presence,
      postgresChanges: clientChanges
    )

    let payload = await RealtimeJoinPayload(
      config: joinConfig,
      accessToken: socket?.accessToken
    )

    joinRef = await socket?.makeRef().description

    logger?.debug("subscribing to channel with body: \(joinConfig)")

    await push(
      RealtimeMessageV2(
        joinRef: joinRef,
        ref: joinRef,
        topic: topic,
        event: ChannelEvent.join,
        payload: try! JSONObject(payload)
      )
    )

    _ = await statusChange.first { @Sendable in $0 == .subscribed }
  }

  public func unsubscribe() async {
    status = .unsubscribing
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

  public func broadcast(event: String, message: some Codable) async throws {
    try await broadcast(event: event, message: JSONObject(message))
  }

  public func broadcast(event: String, message: JSONObject) async {
    assert(
      status == .subscribed,
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
      status == .subscribed,
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
        status = .subscribed

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

        case "SELECT":
          action = .select(
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
  ) -> Subscription {
    let id = callbackManager.addPresenceCallback(callback: callback)
    return Subscription { [weak callbackManager, logger] in
      logger?.debug("Removing presence callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }
  }

  /// Listen for postgres changes in a channel.
  public func onPostgresChange(
    _: InsertAction.Type,
    schema: String = "public",
    table: String? = nil,
    filter: String? = nil,
    callback: @escaping @Sendable (InsertAction) -> Void
  ) -> Subscription {
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
  ) -> Subscription {
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
  ) -> Subscription {
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
  ) -> Subscription {
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

    clientChanges.append(config)

    let id = callbackManager.addPostgresCallback(filter: config, callback: callback)
    return Subscription { [weak callbackManager, logger] in
      logger?.debug("Removing postgres callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }
  }

  /// Listen for broadcast messages sent by other clients within the same channel under a specific `event`.
  public func onBroadcast(
    event: String,
    callback: @escaping @Sendable (JSONObject) -> Void
  ) -> Subscription {
    let id = callbackManager.addBroadcastCallback(event: event, callback: callback)
    return Subscription { [weak callbackManager, logger] in
      logger?.debug("Removing broadcast callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }
  }

  @discardableResult
  private func push(_ message: RealtimeMessageV2) async -> PushStatus {
    let push = PushV2(channel: self, message: message)
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
