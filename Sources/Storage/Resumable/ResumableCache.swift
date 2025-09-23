import Foundation

public struct ResumableCacheEntry: Codable, Sendable {
  public let uploadURL: String
  public let path: String
  public let bucketId: String
  public let expiration: Date
  public let upsert: Bool
  public let contentType: String?

  public init(
    uploadURL: String,
    path: String,
    bucketId: String,
    expiration: Date,
    upsert: Bool,
    contentType: String? = nil
  ) {
    self.uploadURL = uploadURL
    self.path = path
    self.bucketId = bucketId
    self.expiration = expiration
    self.upsert = upsert
    self.contentType = contentType
  }

  enum CodingKeys: String, CodingKey {
    case uploadURL = "upload_url"
    case path
    case bucketId = "bucket_id"
    case expiration
    case upsert
    case contentType = "content_type"
  }
}

public typealias CachePair = (Fingerprint, ResumableCacheEntry)

public protocol ResumableCache: Sendable {
  func set(fingerprint: Fingerprint, entry: ResumableCacheEntry) async throws
  func get(fingerprint: Fingerprint) async throws -> ResumableCacheEntry?
  func remove(fingerprint: Fingerprint) async throws
  func clear() async throws
  func entries() async throws -> [CachePair]
}

public func createDefaultResumableCache() -> some ResumableCache {
  MemoryResumableCache()
}