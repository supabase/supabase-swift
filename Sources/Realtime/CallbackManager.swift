//
//  CallbackManager.swift
//
//
//  Created by Guilherme Souza on 24/12/23.
//

import Foundation
@_spi(Internal) import _Helpers
import ConcurrencyExtras

final class CallbackManager {
  struct MutableState {
    var id = 0
    var serverChanges: [PostgresJoinConfig] = []
    var callbacks: [RealtimeCallback] = []
  }

  let mutableState = LockIsolated(MutableState())

  @discardableResult
  func addBroadcastCallback(event: String, callback: @escaping (AnyJSON) -> Void) -> Int {
    mutableState.withValue {
      $0.id += 1
      $0.callbacks.append(.broadcast(BroadcastCallback(
        id: $0.id,
        event: event,
        callback: callback
      )))
      return $0.id
    }
  }

  @discardableResult
  func addPostgresCallback(
    filter: PostgresJoinConfig,
    callback: @escaping (PostgresAction) -> Void
  ) -> Int {
    mutableState.withValue {
      $0.id += 1
      $0.callbacks.append(.postgres(PostgresCallback(
        id: $0.id,
        filter: filter,
        callback: callback
      )))
      return $0.id
    }
  }

  @discardableResult
  func addPresenceCallback(callback: @escaping (PresenceAction) -> Void) -> Int {
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

  func triggerPostgresChanges(ids: [Int], data: PostgresAction) {
    // Read mutableState at start to acquire lock once.
    let mutableState = mutableState.value

    let filters = mutableState.serverChanges.filter { ids.contains($0.id) }
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

    callbacks.forEach {
      $0.callback(data)
    }
  }

  func triggerBroadcast(event: String, json: AnyJSON) {
    let broadcastCallbacks = mutableState.callbacks.compactMap {
      if case let .broadcast(callback) = $0 {
        return callback
      }
      return nil
    }
    let callbacks = broadcastCallbacks.filter { $0.event == event }
    callbacks.forEach { $0.callback(json) }
  }

  func triggerPresenceDiffs(joins: [String: Presence], leaves: [String: Presence]) {
    let presenceCallbacks = mutableState.callbacks.compactMap {
      if case let .presence(callback) = $0 {
        return callback
      }
      return nil
    }
    presenceCallbacks.forEach { $0.callback(PresenceActionImpl(joins: joins, leaves: leaves)) }
  }
}

struct PostgresCallback {
  var id: Int
  var filter: PostgresJoinConfig
  var callback: (PostgresAction) -> Void
}

struct BroadcastCallback {
  var id: Int
  var event: String
  var callback: (AnyJSON) -> Void
}

struct PresenceCallback {
  var id: Int
  var callback: (PresenceAction) -> Void
}

enum RealtimeCallback {
  case postgres(PostgresCallback)
  case broadcast(BroadcastCallback)
  case presence(PresenceCallback)

  var id: Int {
    switch self {
    case let .postgres(callback): return callback.id
    case let .broadcast(callback): return callback.id
    case let .presence(callback): return callback.id
    }
  }
}
