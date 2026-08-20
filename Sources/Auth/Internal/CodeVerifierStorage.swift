import Foundation
import Logging

/// Stores PKCE code verifiers.
///
/// Verifiers are kept in per-flow slots (keyed by a generated flow id) instead of a single
/// shared slot, so starting several PKCE flows at once — two OAuth sign-ins, or an OAuth flow
/// started while a password reset is pending — doesn't let one flow's verifier overwrite
/// another's. At most ``CodeVerifierStorage/maxConcurrentFlows`` flows are kept pending at
/// once; starting one more evicts the oldest. Every write also updates a legacy fixed-key slot
/// so callers that don't have a flow id (or predate flow ids) keep working against whichever
/// verifier was stored most recently.
struct CodeVerifierStorage: Sendable {
  /// Returns the verifier for `flowId`, or `nil` if none is stored. With `flowId == nil`,
  /// returns the most recently stored verifier.
  var get: @Sendable (_ flowId: String?) -> String?
  /// Stores `code` under a new slot for `flowId`, evicting the oldest pending flow if the
  /// ring is full.
  var set: @Sendable (_ code: String, _ flowId: String) -> Void
  /// Removes the verifier for `flowId`. With `flowId == nil`, removes the legacy fallback slot.
  var remove: @Sendable (_ flowId: String?) -> Void
  /// Removes every pending verifier.
  var removeAll: @Sendable () -> Void
}

extension CodeVerifierStorage {
  static let maxConcurrentFlows = 5

  static func live(clientID: AuthClientID) -> Self {
    var configuration: AuthClient.Configuration { Dependencies[clientID].configuration }

    // Serializes the index read-modify-write in `set`/`remove`/`removeAll`: these are called
    // `nonisolated`, so concurrent flow starts can genuinely run on different threads, not just
    // interleave at await points. Without this, two concurrent writers can each read the index
    // before either writes it back, so one writer's entry is silently dropped, breaking both
    // eviction and `removeAll`'s cleanup for that flow.
    let lock = NSRecursiveLock()

    let baseStorageKey: @Sendable () -> String = {
      configuration.storageKey ?? defaultStorageKey
    }
    let legacyVerifierKey: @Sendable () -> String = { "\(baseStorageKey())-code-verifier" }
    let flowIndexKey: @Sendable () -> String = { "\(baseStorageKey())-flows-code-verifier" }
    let flowSlotKey: @Sendable (String) -> String = { flowId in
      "\(baseStorageKey())-flow-\(flowId)-code-verifier"
    }

    let readString: @Sendable (String) -> String? = { key in
      do {
        guard let data = try configuration.localStorage.retrieve(key: key) else {
          return nil
        }
        return String(decoding: data, as: UTF8.self)
      } catch {
        configuration.logger.error(
          "Failure loading code verifier: \(error.localizedDescription)")
        return nil
      }
    }

    let writeString: @Sendable (String, String) -> Void = { value, key in
      do {
        try configuration.localStorage.store(key: key, value: Data(value.utf8))
      } catch {
        configuration.logger.error(
          "Failure storing code verifier: \(error.localizedDescription)")
      }
    }

    let removeKey: @Sendable (String) -> Void = { key in
      do {
        try configuration.localStorage.remove(key: key)
      } catch {
        configuration.logger.error(
          "Failure removing code verifier: \(error.localizedDescription)")
      }
    }

    let readIndex: @Sendable () -> [String] = {
      readString(flowIndexKey())?.split(separator: "\n").map(String.init) ?? []
    }

    let writeIndex: @Sendable ([String]) -> Void = { index in
      if index.isEmpty {
        removeKey(flowIndexKey())
      } else {
        writeString(index.joined(separator: "\n"), flowIndexKey())
      }
    }

    return Self(
      get: { flowId in
        if let flowId {
          return readString(flowSlotKey(flowId))
        }
        return readString(legacyVerifierKey())
      },
      set: { code, flowId in
        lock.lock()
        defer { lock.unlock() }

        writeString(code, flowSlotKey(flowId))

        var index = readIndex().filter { $0 != flowId }
        index.append(flowId)
        while index.count > maxConcurrentFlows {
          let evicted = index.removeFirst()
          removeKey(flowSlotKey(evicted))
        }
        writeIndex(index)

        // Dual write: exchanges with no flow id (older callers, or callers that never
        // learned this flow's id) fall back to whichever verifier was stored most recently.
        writeString(code, legacyVerifierKey())
      },
      remove: { flowId in
        lock.lock()
        defer { lock.unlock() }

        guard let flowId else {
          removeKey(legacyVerifierKey())
          return
        }

        let slotValue = readString(flowSlotKey(flowId))
        removeKey(flowSlotKey(flowId))
        writeIndex(readIndex().filter { $0 != flowId })

        if let slotValue, slotValue == readString(legacyVerifierKey()) {
          removeKey(legacyVerifierKey())
        }
      },
      removeAll: {
        lock.lock()
        defer { lock.unlock() }

        for flowId in readIndex() {
          removeKey(flowSlotKey(flowId))
        }
        removeKey(flowIndexKey())
        removeKey(legacyVerifierKey())
      }
    )
  }
}
