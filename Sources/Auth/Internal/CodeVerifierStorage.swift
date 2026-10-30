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
  /// Returns the purpose of the flow `flowId`, or `nil` if none is stored. With `flowId == nil`,
  /// returns the purpose of the most recently stored verifier.
  var purpose: @Sendable (_ flowId: String?) -> PendingFlowRecord.Purpose?
  /// Stores `code` and `purpose` under a new slot for `flowId`, evicting the oldest pending flow
  /// if the ring is full.
  var set:
    @Sendable (_ code: String, _ flowId: String, _ purpose: PendingFlowRecord.Purpose) -> Void
  /// Removes the verifier for `flowId`. With `flowId == nil`, removes the legacy fallback slot.
  var remove: @Sendable (_ flowId: String?) -> Void
  /// Removes every pending verifier.
  var removeAll: @Sendable () -> Void
}

extension CodeVerifierStorage {
  static let maxConcurrentFlows = 5

  static func live(
    configuration: AuthClient.Configuration,
    localStorage: any AuthLocalStorage
  ) -> Self {
    let lock = NSRecursiveLock()

    let baseStorageKey: @Sendable () -> String = {
      configuration.storageKey ?? defaultStorageKey
    }
    let legacyVerifierKey: @Sendable () -> String = { "\(baseStorageKey())-code-verifier" }
    let legacyPurposeKey: @Sendable () -> String = { "\(baseStorageKey())-code-verifier-purpose" }
    let flowIndexKey: @Sendable () -> String = { "\(baseStorageKey())-flows-code-verifier" }
    let flowSlotKey: @Sendable (String) -> String = { flowId in
      "\(baseStorageKey())-flow-\(flowId)-code-verifier"
    }
    let flowPurposeKey: @Sendable (String) -> String = { flowId in
      "\(baseStorageKey())-flow-\(flowId)-purpose"
    }

    let readString: @Sendable (String) -> String? = { key in
      do {
        guard let data = try localStorage.retrieve(key: key) else {
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
        try localStorage.store(key: key, value: Data(value.utf8))
      } catch {
        configuration.logger.error(
          "Failure storing code verifier: \(error.localizedDescription)")
      }
    }

    let removeKey: @Sendable (String) -> Void = { key in
      do {
        try localStorage.remove(key: key)
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
      purpose: { flowId in
        readString(flowId.map(flowPurposeKey) ?? legacyPurposeKey())
          .flatMap(PendingFlowRecord.Purpose.init(rawValue:))
      },
      set: { code, flowId, purpose in
        lock.lock()
        defer { lock.unlock() }

        writeString(code, flowSlotKey(flowId))
        writeString(purpose.rawValue, flowPurposeKey(flowId))

        var index = readIndex().filter { $0 != flowId }
        index.append(flowId)
        while index.count > maxConcurrentFlows {
          let evicted = index.removeFirst()
          removeKey(flowSlotKey(evicted))
          removeKey(flowPurposeKey(evicted))
        }
        writeIndex(index)
        writeString(code, legacyVerifierKey())
        writeString(purpose.rawValue, legacyPurposeKey())
      },
      remove: { flowId in
        lock.lock()
        defer { lock.unlock() }

        guard let flowId else {
          removeKey(legacyVerifierKey())
          removeKey(legacyPurposeKey())
          return
        }

        let slotValue = readString(flowSlotKey(flowId))
        removeKey(flowSlotKey(flowId))
        removeKey(flowPurposeKey(flowId))
        writeIndex(readIndex().filter { $0 != flowId })

        if let slotValue, slotValue == readString(legacyVerifierKey()) {
          removeKey(legacyVerifierKey())
          removeKey(legacyPurposeKey())
        }
      },
      removeAll: {
        lock.lock()
        defer { lock.unlock() }

        for flowId in readIndex() {
          removeKey(flowSlotKey(flowId))
          removeKey(flowPurposeKey(flowId))
        }
        removeKey(flowIndexKey())
        removeKey(legacyVerifierKey())
        removeKey(legacyPurposeKey())
      }
    )
  }
}
