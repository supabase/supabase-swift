import ConcurrencyExtras
import Foundation

@MainActor
final class CallbackManager {
  var id = 0
  var serverChanges: [PostgresJoinConfig] = []
  var callbacks: [RealtimeCallback] = []

  @discardableResult
  func addBroadcastCallback(
    event: String,
    callback: @escaping @Sendable (JSONObject) -> Void
  ) -> Int {
    self.id += 1
    self.callbacks.append(
      .broadcast(
        BroadcastCallback(
          id: self.id,
          event: event,
          callback: callback
        )
      )
    )
    return self.id
  }

  @discardableResult
  func addPostgresCallback(
    filter: PostgresJoinConfig,
    callback: @escaping @Sendable (AnyAction) -> Void
  ) -> Int {
      self.id += 1
      self.callbacks.append(
        .postgres(
          PostgresCallback(
            id: self.id,
            filter: filter,
            callback: callback
          )
        )
      )
      return self.id
  }

  @discardableResult
  func addPresenceCallback(callback: @escaping @Sendable (any PresenceAction) -> Void) -> Int {
      self.id += 1
      self.callbacks.append(.presence(PresenceCallback(id: self.id, callback: callback)))
      return self.id
  }

  @discardableResult
  func addSystemCallback(callback: @escaping @Sendable (RealtimeMessageV2) -> Void) -> Int {
      self.id += 1
      self.callbacks.append(.system(SystemCallback(id: self.id, callback: callback)))
      return self.id
  }

  func setServerChanges(changes: [PostgresJoinConfig]) {
      self.serverChanges = changes
  }

  func removeCallback(id: Int) {
      self.callbacks.removeAll { $0.id == id }
  }

  func triggerPostgresChanges(ids: [Int], data: AnyAction) {
    let filters = serverChanges.filter {
      ids.contains($0.id)
    }
    let postgresCallbacks = callbacks.compactMap {
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
    let broadcastCallbacks = callbacks.compactMap {
      if case let .broadcast(callback) = $0 {
        return callback
      }
      return nil
    }
    let callbacks = broadcastCallbacks.filter { $0.event == "*" || $0.event.lowercased() == event.lowercased() }
    callbacks.forEach { $0.callback(json) }
  }

  func triggerPresenceDiffs(
    joins: [String: PresenceV2],
    leaves: [String: PresenceV2],
    rawMessage: RealtimeMessageV2
  ) {
    let presenceCallbacks = callbacks.compactMap {
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

  func triggerSystem(message: RealtimeMessageV2) {
    let systemCallbacks = callbacks.compactMap {
      if case .system(let callback) = $0 {
        return callback
      }
      return nil
    }

    for systemCallback in systemCallbacks {
      systemCallback.callback(message)
    }
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

struct SystemCallback {
  var id: Int
  var callback: @Sendable (RealtimeMessageV2) -> Void
}

enum RealtimeCallback {
  case postgres(PostgresCallback)
  case broadcast(BroadcastCallback)
  case presence(PresenceCallback)
  case system(SystemCallback)

  var id: Int {
    switch self {
    case let .postgres(callback): callback.id
    case let .broadcast(callback): callback.id
    case let .presence(callback): callback.id
    case let .system(callback): callback.id
    }
  }

  var isPresence: Bool {
    if case .presence = self {
      return true
    } else {
      return false
    }
  }
}
