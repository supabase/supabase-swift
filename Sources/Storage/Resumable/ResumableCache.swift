import Foundation

struct ResumableCacheEntry: Codable, Sendable {
  let uploadURL: String
  let path: String
  let bucketId: String
  let expiration: Date
  let upsert: Bool
  let contentType: String?

  enum CodingKeys: String, CodingKey {
    case uploadURL = "upload_url"
    case path
    case bucketId = "bucket_id"
    case expiration
    case upsert
    case contentType = "content_type"
  }
}

typealias CachePair = (Fingerprint, ResumableCacheEntry)

protocol ResumableCache: Sendable {
  func set(fingerprint: Fingerprint, entry: ResumableCacheEntry) async throws
  func get(fingerprint: Fingerprint) async throws -> ResumableCacheEntry?
  func remove(fingerprint: Fingerprint) async throws
  func clear() async throws
  func entries() async throws -> [CachePair]
}

func createDefaultResumableCache() -> some ResumableCache {
  DiskResumableCache(storage: FileManager.default)
}
