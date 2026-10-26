import Foundation

/// Loads the stored session and migrates older formats on the way.
///
/// The first load after an upgrade moves a session from the legacy key `supabase.session` to
/// `key` and rewrites any v2 format as schema 1. Every later load of a stored session is one
/// read of `key`. Decoding and storage errors propagate.
enum PersistedSessionLoader {
  static let legacyKey = "supabase.session"

  static func load(from storage: any AuthStorage, key: String) async throws -> ReceivedSession? {
    let stored = try await storage.load(key: key)
    let legacy = stored == nil ? try await storage.load(key: legacyKey) : nil
    let migration = try migrate(stored: stored, legacy: legacy, key: key)
    for write in migration.writes {
      switch write {
      case .save(let data, let key): try await storage.save(data, key: key)
      case .remove(let key): try await storage.remove(key: key)
      }
    }
    return migration.session
  }

  /// The same load over the synchronous ``AuthLocalStorage``.
  static func load(from storage: any AuthLocalStorage, key: String) throws -> ReceivedSession? {
    let stored = try storage.retrieve(key: key)
    let legacy = stored == nil ? try storage.retrieve(key: legacyKey) : nil
    let migration = try migrate(stored: stored, legacy: legacy, key: key)
    for write in migration.writes {
      switch write {
      case .save(let data, let key): try storage.store(key: key, value: data)
      case .remove(let key): try storage.remove(key: key)
      }
    }
    return migration.session
  }

  private enum Write {
    case save(Data, key: String)
    case remove(key: String)
  }

  /// `legacy` is what the legacy key holds, read only when `key` holds nothing.
  private static func migrate(
    stored: Data?,
    legacy: Data?,
    key: String
  ) throws -> (session: ReceivedSession?, writes: [Write]) {
    if let stored {
      let decoded = try PersistedSessionCodec.decode(stored)
      if decoded.isCurrentSchema {
        return (decoded.session, [])
      }
      return (decoded.session, [.save(try PersistedSessionCodec.encode(decoded.session), key: key)])
    }

    guard let legacy else {
      return (nil, [])
    }
    let decoded = try PersistedSessionCodec.decode(legacy)
    return (
      decoded.session,
      [.save(try PersistedSessionCodec.encode(decoded.session), key: key), .remove(key: legacyKey)]
    )
  }
}
