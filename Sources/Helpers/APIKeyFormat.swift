//
//  APIKeyFormat.swift
//  Supabase
//
//  Created by Claude on 16/07/26.
//

import ConcurrencyExtras
import IssueReporting

/// Classifies and validates the format of a Supabase API key.
///
/// New-format keys (`sb_publishable_…` / `sb_secret_…`) are not JWTs and must never be sent
/// as a Bearer token — they belong only in the `apikey` header. Legacy JWT keys (no `sb_`
/// prefix) and platform-issued temporary keys (`sb_temp_…`) keep the existing Bearer fallback.
package enum APIKeyFormat {
  private static let newFormatPrefixes = ["sb_publishable_", "sb_secret_"]
  private static let temporaryKeyPrefix = "sb_temp_"

  /// Whether `key` is a new-format key (`sb_publishable_…` / `sb_secret_…`).
  package static func isNew(_ key: String) -> Bool {
    newFormatPrefixes.contains { key.hasPrefix($0) }
  }

  private static let warnedSubtypes = LockIsolated<Set<String>>([])

  /// Warns (once per subtype) when `key` has the `sb_` prefix but an unrecognized subtype.
  /// Never throws — the server, not the SDK, decides key validity. The key value is never
  /// included in the message.
  package static func checkFormat(_ key: String) {
    guard shouldWarn(for: key) else { return }
    reportIssue(
      """
      Unrecognized Supabase API key format. The client will proceed and send this key as-is; \
      if you see authentication errors you may need to upgrade supabase-swift to a version \
      that recognizes this key type.
      """
    )
  }

  /// Decides whether `checkFormat` should warn for `key`, and records the subtype as warned
  /// as a side effect. Split out from `checkFormat` so the classification/dedup logic is
  /// unit-testable without exercising `reportIssue` directly (calling `reportIssue` from a
  /// Swift Testing `@Test` function is known to crash the Xcode test runner — see the
  /// `clientInitWithCustomAccessToken` test comment in Tests/SupabaseTests/SupabaseClientTests.swift
  /// for a documented instance of the same constraint).
  package static func shouldWarn(for key: String) -> Bool {
    guard key.hasPrefix("sb_"), !isNew(key), !key.hasPrefix(temporaryKeyPrefix) else {
      return false
    }
    let subtype = subtypeToken(for: key)
    return warnedSubtypes.withValue { $0.insert(subtype).inserted }
  }

  private static func subtypeToken(for key: String) -> String {
    let remainder = key.dropFirst("sb_".count)
    guard let underscoreIndex = remainder.firstIndex(of: "_") else { return "unknown" }
    let candidate = remainder[..<underscoreIndex]
    guard !candidate.isEmpty, candidate.allSatisfy({ $0.isLetter || $0.isNumber }) else {
      return "unknown"
    }
    return String(candidate)
  }
}
