import ConcurrencyExtras
import Foundation
import IssueReporting

/// Reports the first ``AuthError/Kind-swift.struct/storageMisconfigured`` error that the wrapped
/// storage throws as a runtime issue, and rethrows every error.
///
/// A read cannot be the only trigger. Without the Keychain entitlement, the macOS
/// data-protection Keychain answers a read with "no item" and fails only on the first write.
struct MisconfigurationReportingStorage: AuthLocalStorage {
  let base: any AuthLocalStorage
  private let hasReported = LockIsolated(false)

  init(_ base: any AuthLocalStorage) {
    self.base = base
  }

  func store(key: String, value: Data) throws {
    try reporting { try base.store(key: key, value: value) }
  }

  func retrieve(key: String) throws -> Data? {
    try reporting { try base.retrieve(key: key) }
  }

  func remove(key: String) throws {
    try reporting { try base.remove(key: key) }
  }

  private func reporting<T>(_ operation: () throws -> T) throws -> T {
    do {
      return try operation()
    } catch let error as AuthError where error.kind == .storageMisconfigured {
      let isFirst = hasReported.withValue { reported in
        defer { reported = true }
        return !reported
      }
      if isFirst {
        reportIssue(error.message)
      }
      throw error
    }
  }
}
