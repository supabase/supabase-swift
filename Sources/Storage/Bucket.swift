public struct Bucket: Identifiable, Hashable, Codable {
  public var id: String
  public var name: String
  public var owner: String
  public var isPublic: Bool
  public var createdAt: String
  public var updatedAt: String

  public init(
    id: String, name: String, owner: String, isPublic: Bool, createdAt: String, updatedAt: String
  ) {
    self.id = id
    self.name = name
    self.owner = owner
    self.isPublic = isPublic
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case owner
    case isPublic = "public"
    case createdAt = "created_at"
    case updatedAt = "deleted_at"
  }
}
