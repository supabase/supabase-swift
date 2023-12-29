//
//  Channel.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

@_spi(Internal) import _Helpers
import Combine
import ConcurrencyExtras
import Foundation

public struct RealtimeChannelConfig: Sendable {
  public var broadcast: BroadcastJoinConfig
  public var presence: PresenceJoinConfig
}

public final class RealtimeChannelV2: @unchecked Sendable {
  public enum Status: Sendable {
    case unsubscribed
    case subscribing
    case subscribed
    case unsubscribing
  }

  weak var socket: Realtime? {
    didSet {
      assert(oldValue == nil, "socket should not be modified once set")
    }
  }

  let topic: String
  let broadcastJoinConfig: BroadcastJoinConfig
  let presenceJoinConfig: PresenceJoinConfig

  let callbackManager = CallbackManager()

  private let clientChanges: LockIsolated<[PostgresJoinConfig]> = .init([])

  let _status = CurrentValueSubject<Status, Never>(.unsubscribed)
  public lazy var status = _status.share().eraseToAnyPublisher()

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

  deinit {
    callbackManager.reset()
  }

  /// Subscribes to the channel
  /// - Parameter blockUntilSubscribed: if true, the method will block the current Task until the
  /// ``status-swift.property`` is ``Status-swift.enum/subscribed``.
  public func subscribe(blockUntilSubscribed: Bool = false) async {
    if socket?._status.value != .connected {
      if socket?.config.connectOnSubscribe != true {
        fatalError(
          "You can't subscribe to a channel while the realtime client is not connected. Did you forget to call `realtime.connect()`?"
        )
      }
      await socket?.connect()
    }

    socket?.addChannel(self)

    _status.value = .subscribing
    debug("subscribing to channel \(topic)")

    let authToken = await socket?.config.authTokenProvider?.authToken()
    let currentJwt = socket?.config.jwtToken ?? authToken

    let postgresChanges = clientChanges.value

    let joinConfig = RealtimeJoinConfig(
      broadcast: broadcastJoinConfig,
      presence: presenceJoinConfig,
      postgresChanges: postgresChanges,
      accessToken: currentJwt
    )

    debug("subscribing to channel with body: \(joinConfig)")

    try? await socket?.send(
      RealtimeMessageV2(
        joinRef: nil,
        ref: socket?.makeRef().description ?? "",
        topic: topic,
        event: ChannelEvent.join,
        payload: AnyJSON(RealtimeJoinPayload(config: joinConfig)).objectValue ?? [:]
      )
    )

    if blockUntilSubscribed {
      var continuation: CheckedContinuation<Void, Never>?
      let cancellable = status
        .first { $0 == .subscribed }
        .sink { _ in
          continuation?.resume()
        }

      await withTaskCancellationHandler {
        await withCheckedContinuation {
          continuation = $0
        }
      } onCancel: {
        cancellable.cancel()
      }
    }
  }

  public func unsubscribe() async {
    _status.value = .unsubscribing
    debug("unsubscribing from channel \(topic)")

    await socket?.send(
      RealtimeMessageV2(
        joinRef: nil,
        ref: socket?.makeRef().description,
        topic: topic,
        event: ChannelEvent.leave,
        payload: [:]
      )
    )
  }

  public func updateAuth(jwt: String) async {
    debug("Updating auth token for channel \(topic)")
    await socket?.send(
      RealtimeMessageV2(
        joinRef: nil,
        ref: socket?.makeRef().description,
        topic: topic,
        event: ChannelEvent.accessToken,
        payload: ["access_token": .string(jwt)]
      )
    )
  }

  public func broadcast(event: String, message: [String: AnyJSON]) async {
    if _status.value != .subscribed {
      // TODO: use HTTP
    } else {
      await socket?.send(
        RealtimeMessageV2(
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

  public func track(_ state: some Codable) async throws {
    guard let jsonObject = try AnyJSON(state).objectValue else {
      throw RealtimeError("Expected to decode state as a key-value type.")
    }

    await track(state: jsonObject)
  }

  public func track(state: JSONObject) async {
    assert(
      _status.value == .subscribed,
      "You can only track your presence after subscribing to the channel. Did you forget to call `channel.subscribe()`?"
    )

    await socket?.send(RealtimeMessageV2(
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

  public func untrack() async {
    await socket?.send(RealtimeMessageV2(
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

  func onMessage(_ message: RealtimeMessageV2) async {
    do {
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
        let serverPostgresChanges = try message.payload["response"]?
          .objectValue?["postgres_changes"]?
          .decode([PostgresJoinConfig].self)

        callbackManager.setServerChanges(changes: serverPostgresChanges ?? [])

        if _status.value != .subscribed {
          _status.value = .subscribed
          debug("Subscribed to channel \(message.topic)")
        }

      case .postgresChanges:
        guard let data = message.payload["data"] else {
          debug("Expected \"data\" key in message payload.")
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
        let event = message.event
        callbackManager.triggerBroadcast(event: event, message: message)

      case .close:
        await socket?.removeChannel(self)
        debug("Unsubscribed from channel \(message.topic)")

      case .error:
        debug(
          "Received an error in channel ${message.topic}. That could be as a result of an invalid access token"
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
      debug("Failed: \(error)")
    }
  }

  /// Listen for clients joining / leaving the channel using presences.
  public func presenceChange() -> AsyncStream<PresenceAction> {
    let (stream, continuation) = AsyncStream<PresenceAction>.makeStream()

    let id = callbackManager.addPresenceCallback {
      continuation.yield($0)
    }

    continuation.onTermination = { [weak callbackManager] _ in
      debug("Removing presence callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
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
    precondition(
      _status.value != .subscribed,
      "You cannot call postgresChange after joining the channel"
    )

    let (stream, continuation) = AsyncStream<Action>.makeStream()

    let config = PostgresJoinConfig(
      event: Action.eventType,
      schema: schema,
      table: table,
      filter: filter
    )

    clientChanges.withValue { $0.append(config) }

    let id = callbackManager.addPostgresCallback(filter: config) { action in
      if let action = action as? Action {
        continuation.yield(action)
      } else if let action = action.wrappedAction as? Action {
        continuation.yield(action)
      } else {
        assertionFailure(
          "Expected an action of type \(Action.self), but got a \(type(of: action.wrappedAction))."
        )
      }
    }

    continuation.onTermination = { [weak callbackManager] _ in
      debug("Removing postgres callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }

    return stream
  }

  /// Listen for broadcast messages sent by other clients within the same channel under a specific
  /// `event`.
  public func broadcast(event: String) -> AsyncStream<RealtimeMessageV2> {
    let (stream, continuation) = AsyncStream<RealtimeMessageV2>.makeStream()

    let id = callbackManager.addBroadcastCallback(event: event) {
      continuation.yield($0)
    }

    continuation.onTermination = { [weak callbackManager] _ in
      debug("Removing broadcast callback with id: \(id)")
      callbackManager?.removeCallback(id: id)
    }

    return stream
  }
}
