import ConcurrencyExtras
import Foundation

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

  deinit {
    reset()
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

  @discardableResult
  func addSystemCallback(callback: @escaping @Sendable (RealtimeMessageV2) -> Void) -> Int {
    mutableState.withValue {
      $0.id += 1
      $0.callbacks.append(.system(SystemCallback(id: $0.id, callback: callback)))
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
      if case .postgres(let callback) = $0 {
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

  @discardableResult
  func addBroadcastDataCallback(
    event: String,
    callback: @escaping @Sendable (Data) -> Void
  ) -> Int {
    mutableState.withValue {
      $0.id += 1
      $0.callbacks.append(
        .broadcastData(
          BroadcastDataCallback(
            id: $0.id,
            event: event,
            callback: callback
          )
        )
      )
      return $0.id
    }
  }

  func triggerBroadcast(event: String, json: JSONObject) {
    let broadcastCallbacks = mutableState.callbacks.compactMap {
      if case .broadcast(let callback) = $0 {
        return callback
      }
      return nil
    }
    let callbacks = broadcastCallbacks.filter {
      $0.event == "*" || $0.event.lowercased() == event.lowercased()
    }
    callbacks.forEach { $0.callback(json) }
  }

  func triggerBroadcastData(event: String, data: Data) {
    let callbacks = mutableState.callbacks.filter {
      isBroadcastDataCallback(callback: $0, for: event)
    }
    .map { callback -> BroadcastDataCallback in
      if case .broadcastData(let callback) = callback {
        return callback
      } else {
        fatalError("Expected broadcast data callback")
      }
    }
    callbacks.forEach { $0.callback(data) }
  }

  func hasBroadcastDataCallbacks(for event: String) -> Bool {
    mutableState.callbacks.contains {
      isBroadcastDataCallback(callback: $0, for: event)
    }
  }

  private func isBroadcastDataCallback(
    callback: RealtimeCallback,
    for event: String
  ) -> Bool {
    if case .broadcastData(let callback) = callback {
      return callback.event == "*" || callback.event.lowercased() == event.lowercased()
    }
    return false
  }

  func triggerPresenceDiffs(
    joins: [String: PresenceV2],
    leaves: [String: PresenceV2],
    rawMessage: RealtimeMessageV2
  ) {
    let presenceCallbacks = mutableState.callbacks.compactMap {
      if case .presence(let callback) = $0 {
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
    let systemCallbacks = mutableState.callbacks.compactMap {
      if case .system(let callback) = $0 {
        return callback
      }
      return nil
    }

    for systemCallback in systemCallbacks {
      systemCallback.callback(message)
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

struct SystemCallback {
  var id: Int
  var callback: @Sendable (RealtimeMessageV2) -> Void
}

struct BroadcastDataCallback {
  var id: Int
  var event: String
  var callback: @Sendable (Data) -> Void
}

enum RealtimeCallback {
  case postgres(PostgresCallback)
  case broadcast(BroadcastCallback)
  case broadcastData(BroadcastDataCallback)
  case presence(PresenceCallback)
  case system(SystemCallback)

  var id: Int {
    switch self {
    case .postgres(let callback): callback.id
    case .broadcast(let callback): callback.id
    case .broadcastData(let callback): callback.id
    case .presence(let callback): callback.id
    case .system(let callback): callback.id
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
