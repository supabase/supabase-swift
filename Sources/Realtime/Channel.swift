//
//  Channel.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

@_spi(Internal) import _Helpers
import Combine
import Foundation

public struct RealtimeChannelConfig {
  public var broadcast: BroadcastJoinConfig
  public var presence: PresenceJoinConfig
}

public final class RealtimeChannel {
  public enum Status {
    case unsubscribed
    case subscribing
    case subscribed
    case unsubscribing
  }

  weak var socket: Realtime?
  let topic: String
  let broadcastJoinConfig: BroadcastJoinConfig
  let presenceJoinConfig: PresenceJoinConfig

  let callbackManager = CallbackManager()

  private var clientChanges: [PostgresJoinConfig] = []

  let _status = CurrentValueSubject<Status, Never>(.unsubscribed)
  public var status: Status {
    _status.value
  }

  init(
    topic: String,
    socket: Realtime,
    broadcastJoinConfig: BroadcastJoinConfig,
    presenceJoinConfig: PresenceJoinConfig
  ) {
    self.socket = socket
    self.topic = topic
    self.broadcastJoinConfig = broadcastJoinConfig
    self.presenceJoinConfig = presenceJoinConfig
  }

  public func subscribe() async throws {
    if socket?.status != .connected {
      if socket?.config.connectOnSubscribe != true {
        fatalError(
          "You can't subscribe to a channel while the realtime client is not connected. Did you forget to call `realtime.connect()`?"
        )
      }
      try await socket?.connect()
    }

    socket?.addChannel(self)

    _status.value = .subscribing
    debug("subscribing to channel \(topic)")

    let authToken = await socket?.config.authTokenProvider?.authToken()
    let currentJwt = socket?.config.jwtToken ?? authToken

    let postgresChanges = clientChanges

    let joinConfig = RealtimeJoinConfig(
      broadcast: broadcastJoinConfig,
      presence: presenceJoinConfig,
      postgresChanges: postgresChanges
    )

    debug("subscribing to channel with body: \(joinConfig)")

    var config = try AnyJSON(joinConfig).objectValue ?? [:]
    if let currentJwt {
      config["access_token"] = .string(currentJwt)
    }

    try? await socket?.ws?.send(_RealtimeMessage(
      joinRef: nil,
      ref: socket?.makeRef().description ?? "",
      topic: topic,
      event: ChannelEvent.join,
      payload: ["config": .object(config)]
    ))
  }

  public func unsubscribe() async throws {
    _status.value = .unsubscribing
    debug("unsubscribing from channel \(topic)")

    try await socket?.ws?.send(
      _RealtimeMessage(
        joinRef: nil,
        ref: socket?.makeRef().description,
        topic: topic,
        event: ChannelEvent.leave,
        payload: [:]
      )
    )
  }

  public func updateAuth(jwt: String) async throws {
    debug("Updating auth token for channel \(topic)")
    try await socket?.ws?.send(
      _RealtimeMessage(
        joinRef: nil,
        ref: socket?.makeRef().description,
        topic: topic,
        event: ChannelEvent.accessToken,
        payload: ["access_token": .string(jwt)]
      )
    )
  }

  public func broadcast(event: String, message: [String: AnyJSON]) async throws {
    if status != .subscribed {
      // TODO: use HTTP
    } else {
      try await socket?.ws?.send(
        _RealtimeMessage(
          joinRef: nil,
          ref: socket?.makeRef().description,
          topic: topic,
          event: ChannelEvent.broadcast,
          payload: [
            "type": .string("broadcast"),
            "event": .string(event),
            "payload": .object(message),
          ]
        )
      )
    }
  }

  public func track(state: [String: AnyJSON]) async throws {
    guard status == .subscribed else {
      throw RealtimeError(
        "You can only track your presence after subscribing to the channel. Did you forget to call `channel.subscribe()`?"
      )
    }

    try await socket?.ws?.send(_RealtimeMessage(
      joinRef: nil,
      ref: socket?.makeRef().description,
      topic: topic,
      event: ChannelEvent.presence,
      payload: [
        "type": "presence",
        "event": "track",
        "payload": .object(state),
      ]
    ))
  }

  public func untrack() async throws {
    try await socket?.ws?.send(_RealtimeMessage(
      joinRef: nil,
      ref: socket?.makeRef().description,
      topic: topic,
      event: ChannelEvent.presence,
      payload: [
        "type": "presence",
        "event": "untrack",
      ]
    ))
  }

  func onMessage(_ message: _RealtimeMessage) async throws {
    guard let eventType = message.eventType else {
      throw RealtimeError("Received message without event type: \(message)")
    }

    switch eventType {
    case .tokenExpired:
      debug(
        "Received token expired event. This should not happen, please report this warning."
      )

    case .system:
      debug("Subscribed to channel \(message.topic)")
      _status.value = .subscribed

    case .postgresServerChanges:
      let serverPostgresChanges = try message.payload["response"]?.objectValue?["postgres_changes"]?
        .decode([PostgresJoinConfig].self)
      callbackManager.setServerChanges(changes: serverPostgresChanges ?? [])

      if status != .subscribed {
        _status.value = .subscribed
        debug("Subscribed to channel \(message.topic)")
      }

    case .postgresChanges:
      guard let payload = try AnyJSON(message.payload).objectValue,
            let data = payload["data"] else { return }
      let ids = payload["ids"]?.arrayValue?.compactMap(\.intValue) ?? []

      let postgresActions = try data.decode(PostgresActionData.self)

      let action: AnyAction = switch postgresActions.type {
      case "UPDATE":
        .update(UpdateAction(
          columns: postgresActions.columns,
          commitTimestamp: postgresActions.commitTimestamp,
          record: postgresActions.record ?? [:],
          oldRecord: postgresActions.oldRecord ?? [:],
          rawMessage: message
        ))

      case "DELETE":
        .delete(DeleteAction(
          columns: postgresActions.columns,
          commitTimestamp: postgresActions.commitTimestamp,
          oldRecord: postgresActions.oldRecord ?? [:],
          rawMessage: message
        ))

      case "INSERT":
        .insert(InsertAction(
          columns: postgresActions.columns,
          commitTimestamp: postgresActions.commitTimestamp,
          record: postgresActions.record ?? [:],
          rawMessage: message
        ))

      case "SELECT":
        .select(SelectAction(
          columns: postgresActions.columns,
          commitTimestamp: postgresActions.commitTimestamp,
          record: postgresActions.record ?? [:],
          rawMessage: message
        ))

      default:
        throw RealtimeError("Unknown event type: \(postgresActions.type)")
      }

      callbackManager.triggerPostgresChanges(ids: ids, data: action)

    case .broadcast:
      let event = message.event
      let payload = try AnyJSON(message.payload)
      callbackManager.triggerBroadcast(event: event, json: payload)

    case .close:
      try await socket?.removeChannel(self)
      debug("Unsubscribed from channel \(message.topic)")

    case .error:
      debug(
        "Received an error in channel ${message.topic}. That could be as a result of an invalid access token"
      )

    case .presenceDiff:
      let joins: [String: Presence] = [:]
      let leaves: [String: Presence] = [:]
      callbackManager.triggerPresenceDiffs(joins: joins, leaves: leaves)

    case .presenceState:
      let joins: [String: Presence] = [:]
      callbackManager.triggerPresenceDiffs(joins: joins, leaves: [:])
    }
  }

  /// Listen for clients joining / leaving the channel using presences.
  public func presenceChange() -> AsyncStream<PresenceAction> {
    let (stream, continuation) = AsyncStream<PresenceAction>.makeStream()

    let id = callbackManager.addPresenceCallback {
      continuation.yield($0)
    }

    continuation.onTermination = { _ in
      self.callbackManager.removeCallback(id: id)
    }

    return stream
  }

  /// Listen for postgres changes in a channel.
  public func postgresChange<Action: PostgresAction>(
    _ action: Action.Type,
    schema: String = "public",
    table: String,
    filter: String? = nil
  ) -> AsyncStream<Action> {
    precondition(status != .subscribed, "You cannot call postgresChange after joining the channel")

    let (stream, continuation) = AsyncStream<Action>.makeStream()

    let config = PostgresJoinConfig(
      event: Action.eventType,
      schema: schema,
      table: table,
      filter: filter
    )

    clientChanges.append(config)

    let id = callbackManager.addPostgresCallback(filter: config) { action in
      if let action = action.wrappedAction as? Action {
        continuation.yield(action)
      } else {
        assertionFailure(
          "Expected an action of type \(Action.self), but got a \(type(of: action.wrappedAction))."
        )
      }
    }

    continuation.onTermination = { _ in
      self.callbackManager.removeCallback(id: id)
    }

    return stream
  }

  /// Listen for broadcast messages sent by other clients within the same channel under a specific
  /// `event`.
  public func broadcast(event: String) -> AsyncStream<AnyJSON> {
    let (stream, continuation) = AsyncStream<AnyJSON>.makeStream()

    let id = callbackManager.addBroadcastCallback(event: event) {
      continuation.yield($0)
    }

    continuation.onTermination = { _ in
      self.callbackManager.removeCallback(id: id)
    }

    return stream
  }
}
