public import Foundation
public import PostgrestMacros

public enum UserStatus: String, Codable, Hashable, Sendable, PostgrestFilterValue {
  case online = "ONLINE"
  case offline = "OFFLINE"
}

@Table("channels")
public struct Channels {
  @PrimaryKey @Default public var id: Int
  public var slug: String
}

extension Channels.Columns {
  public var channelMessages: PostgrestToManyRelation<Channels, Messages> {
    .init("channel_messages")
  }
  public var firstMessage: PostgrestToOneRelation<Channels, Messages> {
    .init("first_message")
  }
  public var shoutedSlug: PostgrestComputedField<Channels, String> {
    .init("shouted_slug")
  }
}

@Table("counters")
public struct Counters {
  @PrimaryKey @Generated public var id: Int
  public var count: Int
  @Generated public var doubled: Int?
}

@Table("discussions")
public struct Discussions {
  @PrimaryKey @Default public var id: Int
  public var title: String
  public var pinnedPostId: Int?
}

@Table("key_value_storage")
public struct KeyValueStorage {
  @PrimaryKey public var key: String
  public var value: JSONValue?
}

@Table("messages")
public struct Messages {
  @PrimaryKey @Default public var id: Int
  public var channelId: Int?
  public var data: JSONValue?
  public var message: String?
  public var username: String?
}

@Table("note_summaries")
public struct NoteSummaries {
  public var id: Int?
  public var body: String?
  public var bodyLength: Int?
}

@Table("notes")
public struct Notes {
  @PrimaryKey @Default public var id: Int
  public var body: String
}

@Table("posts")
public struct Posts {
  @PrimaryKey @Default public var id: Int
  public var discussionId: Int
  public var author: String
  @Default public var approved: Bool
  @Default public var createdAt: Date
}

@Table("replies")
public struct Replies {
  @PrimaryKey @Default public var id: Int
  public var postId: Int
  public var body: String
  @Default public var approved: Bool
}

@Table("temporal_values")
public struct TemporalValues {
  @PrimaryKey @Generated public var id: Int
  public var atInstant: Date
  public var atLocal: Date
  public var onDay: Date
}

@Table("todos")
public struct Todos {
  @PrimaryKey @Default public var id: UUID
  public var description: String
  @Default public var isComplete: Bool
  @Default public var tags: [String]?
  @Default public var createdAt: Date?
}

@Table("updatable_view")
public struct UpdatableView {
  public var username: String?
  public var nonUpdatableColumn: Int?
}

@Table("users")
public struct Users {
  @PrimaryKey @Default public var id: UUID
  public var email: String?
  public var username: String?
  public var ageRange: JSONValue?
  public var catchphrase: String?
  public var data: JSONValue?
  @Default public var status: UserStatus?
}
