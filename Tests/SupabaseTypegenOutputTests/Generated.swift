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
  public var channelMessages: _PostgrestToManyRelation<Channels, Messages> {
    .init("channel_messages")
  }
  public var firstMessage: _PostgrestToOneRelation<Channels, Messages> {
    .init("first_message")
  }
  public var shoutedSlug: _PostgrestComputedField<Channels, String> {
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

@Table("postgres_values")
public struct PostgresValues {
  @PrimaryKey @Generated public var id: Int
  public var intSpan: _PostgresRange<Int>?
  public var bigSpan: _PostgresRange<Int>?
  public var numSpan: _PostgresRange<Decimal>?
  public var localSpan: _PostgresRange<Date>?
  public var instantSpan: _PostgresRange<Date>?
  public var daySpan: _PostgresRange<Date>?
  public var duration: _PostgresInterval?
  public var atTime: _PostgresTime?
  public var atTimeTz: _PostgresTime?
  public var payload: _PostgresBytes?
  public var address: String?
  public var network: String?
  public var mac: String?
  public var price: String?
  public var document: String?
  public var pair: _PostgresUnmapped?
  public var spot: _PostgresUnmapped?
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
  public var ageRange: _PostgresRange<Int>?
  public var catchphrase: String?
  public var data: JSONValue?
  @Default public var status: UserStatus?
}

@Table("channel_message_counts", readOnly: true)
public struct ChannelMessageCountsRow {
  public var channelId: Int?
  public var messageCount: Int?
  public var slug: String?
}

@Table("get_username_and_status", readOnly: true)
public struct GetUsernameAndStatusRow {
  public var status: UserStatus?
  public var username: String?
}

extension _PostgrestRpc {
  public func channelMessageCounts(minMessages: Int? = nil) throws -> _PostgrestQuery<
    ChannelMessageCountsRow, [ChannelMessageCountsRow]
  > {
    try self.rows("channel_message_counts", arguments: ["min_messages": minMessages])
  }

  public func deleteUser() throws -> _PostgrestFunctionCall<Void> {
    try self.perform("delete_user")
  }

  public func echo(_ body: JSONValue) throws -> _PostgrestFunctionCall<JSONValue?> {
    try self.value("echo", arguments: _PostgrestArguments(body))
  }

  public func getArrayElement(arr: [Int], index: Int) throws -> _PostgrestFunctionCall<Int?> {
    try self.value("get_array_element", arguments: ["arr": arr, "index": index])
  }

  public func getStatus(nameParam: String) throws -> _PostgrestFunctionCall<String?> {
    try self.value("get_status", arguments: ["name_param": nameParam])
  }

  public func getUsernameAndStatus(nameParam: String) throws -> _PostgrestQuery<
    GetUsernameAndStatusRow, [GetUsernameAndStatusRow]
  > {
    try self.rows("get_username_and_status", arguments: ["name_param": nameParam])
  }

  public func messageById(messageId: Int) throws -> _PostgrestFunctionCall<Messages?> {
    try self.row("message_by_id", arguments: ["message_id": messageId])
  }

  public func messageIds(statuses: [UserStatus]) throws -> _PostgrestFunctionCall<[Int?]> {
    try self.value("message_ids", arguments: ["statuses": statuses])
  }

  public func messagesOf(channelId: Int) throws -> _PostgrestQuery<Messages, [Messages]> {
    try self.rows("messages_of", arguments: ["channel_id": channelId])
  }

  public func messagesOf(channelSlug: String, maxCount: Int) throws -> _PostgrestQuery<
    Messages, [Messages]
  > {
    try self.rows("messages_of", arguments: ["channel_slug": channelSlug, "max_count": maxCount])
  }

  public func searchMessages(query: String, channelId: Int? = nil) throws -> _PostgrestQuery<
    Messages, [Messages]
  > {
    try self.rows("search_messages", arguments: ["query": query, "channel_id": channelId])
  }

  public func sleepFor(seconds: Double) throws -> _PostgrestFunctionCall<Void> {
    try self.perform("sleep_for", arguments: ["seconds": seconds])
  }

  public func voidFunc() throws -> _PostgrestFunctionCall<Void> {
    try self.perform("void_func")
  }
}
