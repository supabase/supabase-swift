import Foundation

/// Loads the stored session and migrates older formats on the way.
///
/// The first load after an upgrade moves a session from the legacy key `supabase.session` to
/// `key` and rewrites any v2 format as schema 1. Every later load of a stored session is one
/// `load(key:)`. Decoding and storage errors propagate. Legacy data that does not decode is removed
/// before its error propagates, since the caller only removes `key`.
enum PersistedSessionLoader {
  static let legacyKey = "supabase.session"

  static func load(from storage: any AuthStorage, key: String) async throws -> ReceivedSession? {
    if let data = try await storage.load(key: key) {
      let decoded = try PersistedSessionCodec.decode(data)
      if !decoded.isCurrentSchema {
        try await storage.save(PersistedSessionCodec.encode(decoded.session), key: key)
      }
      return decoded.session
    }

    guard let legacyData = try await storage.load(key: legacyKey) else {
      return nil
    }
    let decoded: PersistedSessionCodec.Decoded
    do {
      decoded = try PersistedSessionCodec.decode(legacyData)
    } catch let error as DecodingError {
      try await storage.remove(key: legacyKey)
      throw error
    }
    try await storage.save(PersistedSessionCodec.encode(decoded.session), key: key)
    try await storage.remove(key: legacyKey)
    return decoded.session
  }
}
