public import Foundation
public import PostgrestMacros

public enum DateSchema: _PostgrestSchema {
  public static let name = "date"
}

public enum MySchema: _PostgrestSchema {
  public static let name = #"my"schema"#
}

public enum InventoryState: String, Codable, Hashable, Sendable, PostgrestFilterValue {
  case inStock = "in stock"
}

public enum MySchemaStatus: String, Codable, Hashable, Sendable, PostgrestFilterValue {
  case on
  case off
}

public enum CodableEnum: String, Codable, Hashable, Sendable, PostgrestFilterValue {
  case a
}

public enum Mood: String, Codable, Hashable, Sendable, PostgrestFilterValue {
  case happy
  case sad
  case selfCase = "self"
  case selfCase2 = "Self"
  case rawValueCase = "rawValue"
  case initCase = "init"
  case inProgress = "in progress"
  case inProgress2 = "in-progress"
  case inProgress3 = "IN_PROGRESS"
  case orderStatusPending = "ORDER_STATUS_PENDING"
  case _1st = "1st"
  case `default`
  case sayHi = #"say "hi""#
  case backSlash = #"back\slash"#
  case unnamed = "__"
}

public enum UserProfiles3: String, Codable, Hashable, Sendable, PostgrestFilterValue {
  case a
}

@Table("class", schema: MySchema.self)
public struct MySchemaClass {
  public var id: Int
}

@Table("UserProfiles")
public struct UserProfiles {
  public var id: Int
}

@Table("coding_keys")
public struct CodingKeysTable {
  public var id: Int
}

@Table("columns")
public struct ColumnsTable {
  public var id: Int
}

@Table("date")
public struct DateTable {
  public var id: Int
}

@Table("draft")
public struct DraftTable {
  public var id: Int
}

@Table("hostile")
public struct Hostile {
  @PrimaryKey public var id: Int
  @Column("class") public var `class`: Int
  @Column("default") public var `default`: String?
  @Column("self") public var selfColumn: Bool
  @Column("Type") public var type: Int
  @Column("init") public var `init`: Int
  @Column("columns") public var columnsColumn: Int
  @Column("select_string") public var selectStringColumn: String
  @Column("relation_name") public var relationNameColumn: String
  @Column("primary_key_columns") public var primaryKeyColumnsColumn: String
  @Column("Draft") public var draft: String
  public var userId: Int
  @Column("userId") public var userId2: Int
  @Column("user-id") public var userId3: Int
  @Column(#"say "hi""#) public var sayHi: String
  @Column(#"back\slash"#) public var backSlash: String
  @Column("1st_place") public var _1stPlace: Int
  @Column("__") public var unnamed: String
  public var rawValue: String
  public var stringValue: String
  public var intValue: Int
  public var hashValue: Int
  public var mood: Mood
  public var moods: [Mood]?
  public var span: _PostgresRange<_Int4Range>?
  public var nick: String
  public var ids: [UUID]?
  public var price: Decimal
  public var ratio: Double
  public var tiny: Int
  public var born: Date
  public var at: Date
  public var code: String
  public var label: String
  public var doc: JSONValue?
  public var stock: InventoryState?
}

extension Hostile.Columns {
  public var selfComputed: _PostgrestComputedField<Hostile, String> {
    .init("Self")
  }
  public var userIdComputed: _PostgrestComputedField<Hostile, String> {
    .init("UserId")
  }
  public var atTime: _PostgrestComputedField<Hostile, Date> {
    .init("at_time")
  }
  public var classes: _PostgrestToManyRelation<Hostile, MySchemaClass> {
    .init("classes")
  }
  public var duration: _PostgrestComputedField<Hostile, _PostgresInterval> {
    .init("duration")
  }
  public var getThings: _PostgrestComputedField<Hostile, Int> {
    .init("getThings")
  }
  public var getThings2: _PostgrestComputedField<Hostile, Int> {
    .init("get_things")
  }
  public var moodsOf: _PostgrestComputedField<Hostile, [Mood]> {
    .init("moods_of")
  }
  public var sayHiBackSlash: _PostgrestComputedField<Hostile, String> {
    .init(#"say "hi" back\slash"#)
  }
  public var shouted: _PostgrestComputedField<Hostile, String> {
    .init("shouted")
  }
  public var tags: _PostgrestComputedField<Hostile, [String]> {
    .init("tags")
  }
  public var weirdMany: _PostgrestToManyRelation<Hostile, WeIrdName> {
    .init("weird_many")
  }
  public var weirdOne: _PostgrestToOneRelation<Hostile, WeIrdName> {
    .init("weird_one")
  }
  public var weirdSingle: _PostgrestToOneRelation<Hostile, WeIrdName> {
    .init("weird_single")
  }
}

@Table("inventory_books")
public struct InventoryBooks {
  public var id: Int
}

@Table("type")
public struct TypeTable {
  public var id: Int
}

@Table("user_profiles")
public struct UserProfiles2 {
  public var id: Int
}

@Table(#"we"ird\name"#)
public struct WeIrdName {
  public var id: Int
}

@Function("today", schema: DateSchema.self)
public struct DateTodayFunction {
  public typealias Result = Date?
}

@Function("restock", schema: MySchema.self)
public struct MySchemaRestockFunction {
  public typealias Result = [MySchemaClass]
  @Column("self") public var selfArgument: Int
  public var `in`: String? = nil
}

@Function("labels")
public struct LabelsFunction {
  public var userId: Int
  @Column("userId") public var userId2: Int
}

@Function("moods")
public struct MoodsFunction {
  public typealias Result = [Mood?]
  public var at: Date
}

@Function("my_schema_restock")
public struct MySchemaRestockFunction2 {
  public typealias Result = [MySchemaClass]
  @Column("self") public var selfArgument: Int
  public var `in`: String? = nil
}

@Function("pick")
public struct PickFunction {
  public typealias Result = Int?
  public var userId: Int
}

@Function("pick")
public struct PickFunction2 {
  public typealias Result = Int?
  @Column("userId") public var userId: Int
}

@Function("rows")
public struct RowsFunction {
  public typealias Result = Int?
}

@Function("self_and_argument")
public struct SelfAndArgumentFunction {
  @Column("self") public var selfArgument2: Int
  public var selfArgument: Int
}

extension _PostgrestFunctions {
  public func dateToday() throws -> _PostgrestFunctionQuery<Date?> {
    try call(DateTodayFunction())
  }

  public func mySchemaRestock(`self` selfArgument: Int, `in`: String? = nil) throws
    -> _PostgrestFunctionQuery<[MySchemaClass]>
  {
    try call(MySchemaRestockFunction(selfArgument: selfArgument, `in`: `in`))
  }

  public func labels(userId: Int, userId2: Int) throws -> _PostgrestFunctionQuery<Void> {
    try call(LabelsFunction(userId: userId, userId2: userId2))
  }

  public func moods(at: Date) throws -> _PostgrestFunctionQuery<[Mood?]> {
    try call(MoodsFunction(at: at))
  }

  public func mySchemaRestock2(`self` selfArgument: Int, `in`: String? = nil) throws
    -> _PostgrestFunctionQuery<[MySchemaClass]>
  {
    try call(MySchemaRestockFunction2(selfArgument: selfArgument, `in`: `in`))
  }

  public func pick(userId: Int) throws -> _PostgrestFunctionQuery<Int?> {
    try call(PickFunction(userId: userId))
  }

  public func pick2(userId: Int) throws -> _PostgrestFunctionQuery<Int?> {
    try call(PickFunction2(userId: userId))
  }

  public func rows() throws -> _PostgrestFunctionQuery<Int?> {
    try call(RowsFunction())
  }

  public func selfAndArgument(`self` selfArgument2: Int, selfArgument: Int) throws
    -> _PostgrestFunctionQuery<Void>
  {
    try call(SelfAndArgumentFunction(selfArgument2: selfArgument2, selfArgument: selfArgument))
  }
}
