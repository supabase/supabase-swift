public struct Bucket: Hashable {
  public var id: String
  public var name: String
  public var owner: String
  public var isPublic: Bool
  public var createdAt: String
  public var updatedAt: String

  init?(from dictionary: [String: Any]) {
    guard
      let id = dictionary["id"] as? String,
      let name = dictionary["name"] as? String,
      let owner = dictionary["owner"] as? String,
      let createdAt = dictionary["created_at"] as? String,
      let updatedAt = dictionary["updated_at"] as? String,
      let isPublic = dictionary["public"] as? Bool
    else {
      return nil
    }

    self.id = id
    self.name = name
    self.owner = owner
    self.isPublic = isPublic
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
