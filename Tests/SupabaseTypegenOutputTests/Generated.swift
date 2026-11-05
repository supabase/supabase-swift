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
  public var intSpan: _PostgresRange<_Int4Range>?
  public var bigSpan: _PostgresRange<_Int8Range>?
  public var numSpan: _PostgresRange<_NumRange>?
  public var localSpan: _PostgresRange<_TSRange>?
  public var instantSpan: _PostgresRange<_TSTZRange>?
  public var daySpan: _PostgresRange<_DateRange>?
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
  public var ageRange: _PostgresRange<_Int4Range>?
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

@Function("channel_message_counts")
public struct ChannelMessageCountsFunction {
  public typealias Result = [ChannelMessageCountsRow]
  public var minMessages: Int? = nil
}

@Function("delete_user")
public struct DeleteUserFunction {
}

public struct EchoFunction: _PostgrestFunction {
  public static var functionName: String {
    "echo"
  }
  public typealias Result = JSONValue?
  var body: JSONValue
  public func encode(to encoder: any Encoder) throws {
    try body.encode(to: encoder)
  }
}

@Function("get_array_element")
public struct GetArrayElementFunction {
  public typealias Result = Int?
  public var arr: [Int]
  public var index: Int
}

@Function("get_status")
public struct GetStatusFunction {
  public typealias Result = String?
  public var nameParam: String
}

@Function("get_username_and_status")
public struct GetUsernameAndStatusFunction {
  public typealias Result = [GetUsernameAndStatusRow]
  public var nameParam: String
}

@Function("message_ids")
public struct MessageIdsFunction {
  public typealias Result = [Int?]
  public var statuses: [UserStatus]
}

@Function("messages_of")
public struct MessagesOfFunction {
  public typealias Result = [Messages]
  public var channelId: Int
}

@Function("messages_of")
public struct MessagesOfFunction2 {
  public typealias Result = [Messages]
  public var channelSlug: String
  public var maxCount: Int
}

@Function("search_messages")
public struct SearchMessagesFunction {
  public typealias Result = [Messages]
  public var query: String
  public var channelId: Int? = nil
}

@Function("sleep_for")
public struct SleepForFunction {
  public var seconds: Double
}

@Function("void_func")
public struct VoidFuncFunction {
}

extension _PostgrestFunctions {
  public func channelMessageCounts(minMessages: Int? = nil) throws -> _PostgrestFunctionQuery<
    [ChannelMessageCountsRow]
  > {
    try call(ChannelMessageCountsFunction(minMessages: minMessages))
  }

  public func deleteUser() throws -> _PostgrestFunctionQuery<Void> {
    try call(DeleteUserFunction())
  }

  public func echo(_ body: JSONValue) throws -> _PostgrestFunctionQuery<JSONValue?> {
    try call(EchoFunction(body: body))
  }

  public func getArrayElement(arr: [Int], index: Int) throws -> _PostgrestFunctionQuery<Int?> {
    try call(GetArrayElementFunction(arr: arr, index: index))
  }

  public func getStatus(nameParam: String) throws -> _PostgrestFunctionQuery<String?> {
    try call(GetStatusFunction(nameParam: nameParam))
  }

  public func getUsernameAndStatus(nameParam: String) throws -> _PostgrestFunctionQuery<
    [GetUsernameAndStatusRow]
  > {
    try call(GetUsernameAndStatusFunction(nameParam: nameParam))
  }

  public func messageIds(statuses: [UserStatus]) throws -> _PostgrestFunctionQuery<[Int?]> {
    try call(MessageIdsFunction(statuses: statuses))
  }

  public func messagesOf(channelId: Int) throws -> _PostgrestFunctionQuery<[Messages]> {
    try call(MessagesOfFunction(channelId: channelId))
  }

  public func messagesOf(channelSlug: String, maxCount: Int) throws -> _PostgrestFunctionQuery<
    [Messages]
  > {
    try call(MessagesOfFunction2(channelSlug: channelSlug, maxCount: maxCount))
  }

  public func searchMessages(query: String, channelId: Int? = nil) throws
    -> _PostgrestFunctionQuery<[Messages]>
  {
    try call(SearchMessagesFunction(query: query, channelId: channelId))
  }

  public func sleepFor(seconds: Double) throws -> _PostgrestFunctionQuery<Void> {
    try call(SleepForFunction(seconds: seconds))
  }

  public func voidFunc() throws -> _PostgrestFunctionQuery<Void> {
    try call(VoidFuncFunction())
  }
}
