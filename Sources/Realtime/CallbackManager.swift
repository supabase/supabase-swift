//
//  CallbackManager.swift
//
//
//  Created by Guilherme Souza on 24/12/23.
//

import ConcurrencyExtras
import Foundation
import Helpers

final class CallbackManager: Sendable {
  struct MutableState {
    var id = 0
    var serverChanges: [PostgresJoinConfig] = []
    var callbacks: [RealtimeCallback] = []
  }

  private let mutableState = LockIsolated(MutableState())

  var serverChanges: [PostgresJoinConfig] {
    mutableState.serverChanges
  }

  var callbacks: [RealtimeCallback] {
    mutableState.callbacks
  }

  @discardableResult
  func addBroadcastCallback(
    event: String,
    callback: @escaping @Sendable (JSONObject) -> Void
  ) -> Int {
    mutableState.withValue {
      $0.id += 1
      $0.callbacks.append(
        .broadcast(
          BroadcastCallback(
            id: $0.id,
            event: event,
            callback: callback
          )
        )
      )
      return $0.id
    }
  }

  @discardableResult
  func addPostgresCallback(
    filter: PostgresJoinConfig,
    callback: @escaping @Sendable (AnyAction) -> Void
  ) -> Int {
    mutableState.withValue {
      $0.id += 1
      $0.callbacks.append(
        .postgres(
          PostgresCallback(
            id: $0.id,
            filter: filter,
            callback: callback
          )
        )
      )
      return $0.id
    }
  }

  @discardableResult
  func addPresenceCallback(callback: @escaping @Sendable (any PresenceAction) -> Void) -> Int {
    mutableState.withValue {
      $0.id += 1
      $0.callbacks.append(.presence(PresenceCallback(id: $0.id, callback: callback)))
      return $0.id
    }
  }

  func setServerChanges(changes: [PostgresJoinConfig]) {
    mutableState.withValue {
      $0.serverChanges = changes
    }
  }

  func removeCallback(id: Int) {
    mutableState.withValue {
      $0.callbacks.removeAll { $0.id == id }
    }
  }

  func triggerPostgresChanges(ids: [Int], data: AnyAction) {
    // Read mutableState at start to acquire lock once.
    let mutableState = mutableState.value

    let filters = mutableState.serverChanges.filter {
      ids.contains($0.id)
    }
    let postgresCallbacks = mutableState.callbacks.compactMap {
      if case let .postgres(callback) = $0 {
        return callback
      }
      return nil
    }

    let callbacks = postgresCallbacks.filter { cc in
      filters.contains { sc in
        cc.filter == sc
      }
    }

    for item in callbacks {
      item.callback(data)
    }
  }

  func triggerBroadcast(event: String, json: JSONObject) {
    let broadcastCallbacks = mutableState.callbacks.compactMap {
      if case let .broadcast(callback) = $0 {
        return callback
      }
      return nil
    }
    let callbacks = broadcastCallbacks.filter { $0.event == event }
    callbacks.forEach { $0.callback(json) }
  }

  func triggerPresenceDiffs(
    joins: [String: PresenceV2],
    leaves: [String: PresenceV2],
    rawMessage: RealtimeMessage
  ) {
    let presenceCallbacks = mutableState.callbacks.compactMap {
      if case let .presence(callback) = $0 {
        return callback
      }
      return nil
    }
    for presenceCallback in presenceCallbacks {
      presenceCallback.callback(
        PresenceActionImpl(
          joins: joins,
          leaves: leaves,
          rawMessage: rawMessage
        )
      )
    }
  }

  func reset() {
    mutableState.setValue(MutableState())
  }
}

struct PostgresCallback {
  var id: Int
  var filter: PostgresJoinConfig
  var callback: @Sendable (AnyAction) -> Void
}

struct BroadcastCallback {
  var id: Int
  var event: String
  var callback: @Sendable (JSONObject) -> Void
}

struct PresenceCallback {
  var id: Int
  var callback: @Sendable (any PresenceAction) -> Void
}

enum RealtimeCallback {
  case postgres(PostgresCallback)
  case broadcast(BroadcastCallback)
  case presence(PresenceCallback)

  var id: Int {
    switch self {
    case let .postgres(callback): callback.id
    case let .broadcast(callback): callback.id
    case let .presence(callback): callback.id
    }
  }
}
