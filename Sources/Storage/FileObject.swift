import Foundation
import Helpers

public struct FileObject: Identifiable, Hashable, Codable, Sendable {
  public var name: String?
  public var bucketId: String?
  public var owner: String?
  public var id: UUID?
  public var updatedAt: Date?
  public var createdAt: Date?
  public var lastAccessedAt: Date?
  public var metadata: [String: AnyJSON]?

  public init(
    name: String? = nil,
    bucketId: String? = nil,
    owner: String? = nil,
    id: UUID?,
    updatedAt: Date? = nil,
    createdAt: Date? = nil,
    lastAccessedAt: Date? = nil,
    metadata: [String: AnyJSON]? = nil
  ) {
    self.name = name
    self.bucketId = bucketId
    self.owner = owner
    self.id = id
    self.updatedAt = updatedAt
    self.createdAt = createdAt
    self.lastAccessedAt = lastAccessedAt
    self.metadata = metadata
  }

  enum CodingKeys: String, CodingKey {
    case name
    case bucketId = "bucket_id"
    case owner
    case id
    case updatedAt = "updated_at"
    case createdAt = "created_at"
    case lastAccessedAt = "last_accessed_at"
    case metadata
  }
}
