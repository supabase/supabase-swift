import Foundation

public actor MemoryResumableCache: ResumableCache {
  private var storage: [String: Data] = [:]

  public init() {}

  public func set(fingerprint: Fingerprint, entry: ResumableCacheEntry) async throws {
    let data = try JSONEncoder().encode(entry)
    storage[fingerprint.value] = data
  }

  public func get(fingerprint: Fingerprint) async throws -> ResumableCacheEntry? {
    guard let data = storage[fingerprint.value] else {
      return nil
    }
    return try JSONDecoder().decode(ResumableCacheEntry.self, from: data)
  }

  public func remove(fingerprint: Fingerprint) async throws {
    storage.removeValue(forKey: fingerprint.value)
  }

  public func clear() async throws {
    storage.removeAll()
  }

  public func entries() async throws -> [CachePair] {
    var pairs: [CachePair] = []

    for (key, data) in storage {
      guard let fingerprint = Fingerprint(value: key) else {
        continue
      }

      do {
        let entry = try JSONDecoder().decode(ResumableCacheEntry.self, from: data)
        pairs.append((fingerprint, entry))
      } catch {
        continue
      }
    }

    return pairs
  }
}