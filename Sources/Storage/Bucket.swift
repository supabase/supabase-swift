import Foundation

public struct Bucket: Identifiable, Hashable, Codable, Sendable {
  public var id: String
  public var name: String
  public var owner: String?
  public var isPublic: Bool?
  public var createdAt: Date?
  public var updatedAt: Date?
  public var allowedMimeTypes: [String]?
  public var fileSizeLimit: Int64?

  public init(
    id: String,
    name: String,
    owner: String? = nil,
    isPublic: Bool? = nil,
    createdAt: Date? = nil,
    updatedAt: Date? = nil,
    allowedMimeTypes: [String]? = nil,
    fileSizeLimit: Int64? = nil
  ) {
    self.id = id
    self.name = name
    self.owner = owner
    self.isPublic = isPublic
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.allowedMimeTypes = allowedMimeTypes
    self.fileSizeLimit = fileSizeLimit
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case owner
    case isPublic = "public"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case allowedMimeTypes = "allowed_mime_types"
    case fileSizeLimit = "file_size_limit"
  }
}
