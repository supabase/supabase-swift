import ConcurrencyExtras
import Foundation
import IssueReporting

/// Reports the first ``AuthError/Kind-swift.struct/storageMisconfigured`` error that the wrapped
/// storage throws as a runtime issue, and rethrows every error.
///
/// A read cannot be the only trigger. Without the Keychain entitlement, the macOS
/// data-protection Keychain answers a read with "no item" and fails only on the first write.
struct MisconfigurationReportingStorage: AuthStorage {
  let base: any AuthStorage
  private let hasReported = LockIsolated(false)

  init(_ base: any AuthStorage) {
    self.base = base
  }

  func save(_ data: Data, key: String) async throws {
    try await reporting { try await base.save(data, key: key) }
  }

  func load(key: String) async throws -> Data? {
    try await reporting { try await base.load(key: key) }
  }

  func remove(key: String) async throws {
    try await reporting { try await base.remove(key: key) }
  }

  private func reporting<T>(_ operation: () async throws -> T) async throws -> T {
    do {
      return try await operation()
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
