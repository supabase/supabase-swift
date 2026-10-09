public import Foundation
public import PostgrestMacros

public enum Inventory: _PostgrestSchema {
  public static let name = "inventory"
}

public enum InventoryUserStatus: String, Codable, Hashable, Sendable, PostgrestFilterValue {
  case stocked = "STOCKED"
  case discontinued = "DISCONTINUED"
}

public enum MemeStatus: String, Codable, Hashable, Sendable, PostgrestFilterValue {
  case new
  case old
  case retired
}

public enum UserStatus: String, Codable, Hashable, Sendable, PostgrestFilterValue {
  case active = "ACTIVE"
  case inactive = "INACTIVE"
}

@Table("items", schema: Inventory.self)
public struct InventoryItems {
  @PrimaryKey @Default public var id: Int
  public var ownerId: Int
  @Default public var status: InventoryUserStatus
}

@Table("users", schema: Inventory.self)
public struct InventoryUsers {
  @PrimaryKey @Default public var id: Int
  @Default public var status: InventoryUserStatus?
  public var publicUserId: Int?
}

@Table("a_view")
public struct AView {
  public var id: Int?
}

@Table("category")
public struct Category {
  @PrimaryKey @Default public var id: Int
  public var name: String
}

@Table("empty")
public struct Empty {
}

@Table("events")
public struct Events {
  @PrimaryKey @Default public var id: Int
  @PrimaryKey @Default public var createdAt: Date
  public var eventType: String?
  public var data: JSONValue?
}

extension Events.Columns {
  public var daysSinceEvent: _PostgrestComputedField<Events, Decimal> {
    .init("days_since_event")
  }
}

@Table("events_2024")
public struct Events2024 {
  @PrimaryKey public var id: Int
  @PrimaryKey @Default public var createdAt: Date
  public var eventType: String?
  public var data: JSONValue?
}

@Table("events_2025")
public struct Events2025 {
  @PrimaryKey public var id: Int
  @PrimaryKey @Default public var createdAt: Date
  public var eventType: String?
  public var data: JSONValue?
}

@Table("foreign_table", readOnly: true)
public struct ForeignTable {
  public var id: Int
  public var name: String?
  public var status: UserStatus?
}

extension ForeignTable.Columns {
  public var foreignTableLabel: _PostgrestComputedField<ForeignTable, String> {
    .init("foreign_table_label")
  }
}

@Table("interval_test")
public struct IntervalTest {
  @PrimaryKey @Default public var id: Int
  public var durationRequired: JSONValue
  public var durationOptional: JSONValue?
}

extension IntervalTest.Columns {
  public var doubleDuration: _PostgrestComputedField<IntervalTest, JSONValue> {
    .init("double_duration")
  }
}

@Table("memes")
public struct Memes {
  @PrimaryKey @Default public var id: Int
  public var name: String
  public var category: Int?
  public var metadata: JSONValue?
  public var createdAt: Date
  @Default public var status: MemeStatus?
}

@Table("scalar_type_test")
public struct ScalarTypeTest {
  @PrimaryKey @Default public var id: Int
  public var flag: Bool
  public var smallInt: Int?
  public var singlePrecision: Double?
  public var doublePrecision: Double?
}

@Table("table_with_other_tables_row_type")
public struct TableWithOtherTablesRowType {
  public var col1: JSONValue?
  public var col2: JSONValue?
}

@Table("table_with_primary_key_other_than_id")
public struct TableWithPrimaryKeyOtherThanId {
  @PrimaryKey @Default public var otherId: Int
  public var name: String?
}

@Table("todos")
public struct Todos {
  @PrimaryKey @Default public var id: Int
  public var details: String?
  @Column("user-id") public var userId: Int
}

extension Todos.Columns {
  public var blurb: _PostgrestComputedField<Todos, String> {
    .init("blurb")
  }
  public var blurbVarchar: _PostgrestComputedField<Todos, String> {
    .init("blurb_varchar")
  }
  public var detailsIsLong: _PostgrestComputedField<Todos, Bool> {
    .init("details_is_long")
  }
  public var detailsLength: _PostgrestComputedField<Todos, Int> {
    .init("details_length")
  }
  public var detailsWords: _PostgrestComputedField<Todos, [String]> {
    .init("details_words")
  }
  public var functionReturningSingleRow: _PostgrestToOneRelation<Todos, Users> {
    .init("function_returning_single_row")
  }
  public var getTodosSetofRows: _PostgrestToManyRelation<Todos, Todos> {
    .init("get_todos_setof_rows")
  }
  public var testUnnamedRowScalar: _PostgrestComputedField<Todos, Int> {
    .init("test_unnamed_row_scalar")
  }
  public var testUnnamedRowSetof: _PostgrestToManyRelation<Todos, Todos> {
    .init("test_unnamed_row_setof")
  }
}

@Table("todos_matview", readOnly: true)
public struct TodosMatview {
  public var id: Int?
  public var details: String?
  @Column("user-id") public var userId: Int?
}

extension TodosMatview.Columns {
  public var getTodosByMatview: _PostgrestToOneRelation<TodosMatview, Todos> {
    .init("get_todos_by_matview")
  }
  public var todosMatviewLabel: _PostgrestComputedField<TodosMatview, String> {
    .init("todos_matview_label")
  }
}

@Table("todos_view")
public struct TodosView {
  public var id: Int?
  public var details: String?
  @Column("user-id") public var userId: Int?
}

extension TodosView.Columns {
  public var blurbVarchar: _PostgrestComputedField<TodosView, String> {
    .init("blurb_varchar")
  }
  public var testUnnamedViewRow: _PostgrestToManyRelation<TodosView, Todos> {
    .init("test_unnamed_view_row")
  }
}

@Table("user_details")
public struct UserDetails {
  @PrimaryKey public var userId: Int
  public var details: String?
}

@Table("user_todos_summary_view", readOnly: true)
public struct UserTodosSummaryView {
  public var userId: Int?
  public var userName: String?
  public var userStatus: UserStatus?
  public var todoCount: Int?
  public var todoDetails: [String]?
}

@Table("users")
public struct Users {
  @PrimaryKey @Default public var id: Int
  public var name: String?
  @Default public var status: UserStatus?
  public var decimal: Decimal?
  @Default public var userUuid: UUID?
}

extension Users.Columns {
  public var functionUsingSetofRowsOne: _PostgrestToOneRelation<Users, Todos> {
    .init("function_using_setof_rows_one")
  }
  public var functionUsingTableReturns: _PostgrestToOneRelation<Users, Todos> {
    .init("function_using_table_returns")
  }
  public var getSingleUserSummaryFromView: _PostgrestToOneRelation<Users, UserTodosSummaryView> {
    .init("get_single_user_summary_from_view")
  }
  public var getTodosFromUser: _PostgrestToManyRelation<Users, Todos> {
    .init("get_todos_from_user")
  }
  public var getTodosSetofRows: _PostgrestToManyRelation<Users, Todos> {
    .init("get_todos_setof_rows")
  }
  public var getUserAuditSetofSingleRow: _PostgrestToOneRelation<Users, UsersAudit> {
    .init("get_user_audit_setof_single_row")
  }
  public var postgrestResolvableWithOverrideFunction: _PostgrestToManyRelation<Users, Todos> {
    .init("postgrest_resolvable_with_override_function")
  }
  public var testUnnamedRowSetof: _PostgrestToManyRelation<Users, Todos> {
    .init("test_unnamed_row_setof")
  }
}

@Table("users_audit")
public struct UsersAudit {
  @Default public var id: Int
  @Default public var createdAt: Date?
  public var userId: Int?
  public var previousValue: JSONValue?
}

extension UsersAudit.Columns {
  public var createdAgo: _PostgrestComputedField<UsersAudit, Decimal> {
    .init("created_ago")
  }
}

@Table("users_view")
public struct UsersView {
  public var id: Int?
  public var name: String?
  public var status: UserStatus?
  public var decimal: Decimal?
  public var userUuid: UUID?
}

extension UsersView.Columns {
  public var getSingleUserSummaryFromView: _PostgrestToOneRelation<UsersView, UserTodosSummaryView>
  {
    .init("get_single_user_summary_from_view")
  }
  public var getTodosFromUser: _PostgrestToManyRelation<UsersView, Todos> {
    .init("get_todos_from_user")
  }
}

@Table("users_view_with_multiple_refs_to_users", readOnly: true)
public struct UsersViewWithMultipleRefsToUsers {
  public var initialId: Int?
  public var initialName: String?
  public var secondId: Int?
  public var secondName: String?
}
