//
//  TableMacroTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import MacroTesting
import Testing

@testable import PostgrestMacrosPlugin

/// `MacroTesting` expands the macro without its declaration, so `conformingTo:` is always empty
/// here and the recorded extensions carry no inheritance clause. `TableMacroSupportTests` asserts
/// the clause directly.
@Suite(.macros(["Table": TableMacro.self]))
struct TableMacroTests {
  /// A generated surrogate key: `@Default` is what makes it optional in `Draft`, not
  /// `@PrimaryKey`. See `draftOnATableThatIsNothingButACompoundKey` for a key without it.
  @Test
  func expandsAWritableTable() {
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey @Default var id: Int
        var task: String
        @Default var isDone: Bool
        @Column("due_at") var dueDate: Date?
      }
      """
    } expansion: {
      """
      struct Todo {
        @PrimaryKey @Default var id: Int
        var task: String
        @Default var isDone: Bool
        @Column("due_at") var dueDate: Date?
      }

      extension Todo {
        static let relationName = "todos"

        static let schema = "public"

        static let selectString = "*"

        struct Columns: Sendable {
          let id = PostgrestColumn<Todo, Int>("id")
          let task = PostgrestColumn<Todo, String>("task")
          let isDone = PostgrestColumn<Todo, Bool>("is_done")
          let dueDate = PostgrestNullableColumn<Todo, Date>("due_at")

          init() {
          }
        }

        static let columns = Columns()

        static let primaryKeyColumns: [String] = ["id"]

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
          case isDone = "is_done"
          case dueDate = "due_at"
        }

        struct Draft: Encodable, Sendable {
          var id: Int?
          var task: String
          var isDone: Bool?
          var dueDate: Date?

          enum CodingKeys: String, CodingKey {
            case id = "id"
            case task = "task"
            case isDone = "is_done"
            case dueDate = "due_at"
          }

          init(id: Int? = nil, task: String, isDone: Bool? = nil, dueDate: Date? = nil) {
            self.id = id
            self.task = task
            self.isDone = isDone
            self.dueDate = dueDate
          }
        }
      }
      """
    }
  }

  @Test
  func readOnlyTableOmitsTheDraftShape() {
    assertMacro {
      """
      @Table("active_todos", readOnly: true)
      struct ActiveTodo {
        var id: Int
      }
      """
    } expansion: {
      """
      struct ActiveTodo {
        var id: Int
      }

      extension ActiveTodo {
        static let relationName = "active_todos"

        static let schema = "public"

        static let selectString = "*"

        struct Columns: Sendable {
          let id = PostgrestColumn<ActiveTodo, Int>("id")

          init() {
          }
        }

        static let columns = Columns()

        enum CodingKeys: String, CodingKey {
          case id = "id"
        }
      }
      """
    }
  }

  @Test
  func aWritableTableWithNoKeyOmitsPrimaryKeyColumns() {
    // `primaryKeyColumns` is mandatory on `PostgrestKeyedRelation`, so not emitting it is what
    // keeps this type off that protocol — and off the derived-target `upsert` with it. Emitting an
    // empty literal would conform it and send an empty `on_conflict`, a different request.
    assertMacro {
      """
      @Table("audit_events")
      struct AuditEvent {
        var action: String
      }
      """
    } expansion: {
      #"""
      struct AuditEvent {
        var action: String
      }

      extension AuditEvent {
        static let relationName = "audit_events"

        static let schema = "public"

        static let selectString = "*"

        struct Columns: Sendable {
          let action = PostgrestColumn<AuditEvent, String>("action")

          init() {
          }
        }

        static let columns = Columns()

        enum CodingKeys: String, CodingKey {
          case action = "action"
        }

        struct Draft: Encodable, Sendable {
          var action: String

          enum CodingKeys: String, CodingKey {
            case action = "action"
          }

          init(action: String) {
            self.action = action
          }
        }
      }
      """#
    }
  }

  @Test
  func propagatesTheAccessLevel() {
    assertMacro {
      """
      @Table("todos", schema: "app")
      public struct Todo {
        @PrimaryKey var id: Int
        var task: String
      }
      """
    } expansion: {
      """
      public struct Todo {
        @PrimaryKey var id: Int
        var task: String
      }

      extension Todo {
        public static let relationName = "todos"

        public static let schema = "app"

        public static let selectString = "*"

        public struct Columns: Sendable {
          public let id = PostgrestColumn<Todo, Int>("id")
          public let task = PostgrestColumn<Todo, String>("task")

          public init() {
          }
        }

        public static let columns = Columns()

        public static let primaryKeyColumns: [String] = ["id"]

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
        }

        public struct Draft: Encodable, Sendable {
          public var id: Int
          public var task: String

          enum CodingKeys: String, CodingKey {
            case id = "id"
            case task = "task"
          }

          public init(id: Int, task: String) {
            self.id = id
            self.task = task
          }
        }
      }
      """
    }
  }

  @Test
  func skipsComputedAndStaticMembers() {
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        static let table = "todos"
        var htmlURL: String
        var summary: String { htmlURL }
      }
      """
    } expansion: {
      """
      struct Todo {
        static let table = "todos"
        var htmlURL: String
        var summary: String { htmlURL }
      }

      extension Todo {
        static let relationName = "todos"

        static let schema = "public"

        static let selectString = "*"

        struct Columns: Sendable {
          let htmlURL = PostgrestColumn<Todo, String>("html_url")

          init() {
          }
        }

        static let columns = Columns()

        enum CodingKeys: String, CodingKey {
          case htmlURL = "html_url"
        }

        struct Draft: Encodable, Sendable {
          var htmlURL: String

          enum CodingKeys: String, CodingKey {
            case htmlURL = "html_url"
          }

          init(htmlURL: String) {
            self.htmlURL = htmlURL
          }
        }
      }
      """
    }
  }
  @Test
  func coversEveryBindingInAMultiBindingDeclaration() {
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var task: String, note: String
        var draft, review: String
      }
      """
    } expansion: {
      """
      struct Todo {
        @PrimaryKey var id: Int
        var task: String, note: String
        var draft, review: String
      }

      extension Todo {
        static let relationName = "todos"

        static let schema = "public"

        static let selectString = "*"

        struct Columns: Sendable {
          let id = PostgrestColumn<Todo, Int>("id")
          let task = PostgrestColumn<Todo, String>("task")
          let note = PostgrestColumn<Todo, String>("note")
          let draft = PostgrestColumn<Todo, String>("draft")
          let review = PostgrestColumn<Todo, String>("review")

          init() {
          }
        }

        static let columns = Columns()

        static let primaryKeyColumns: [String] = ["id"]

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
          case note = "note"
          case draft = "draft"
          case review = "review"
        }

        struct Draft: Encodable, Sendable {
          var id: Int
          var task: String
          var note: String
          var draft: String
          var review: String

          enum CodingKeys: String, CodingKey {
            case id = "id"
            case task = "task"
            case note = "note"
            case draft = "draft"
            case review = "review"
          }

          init(id: Int, task: String, note: String, draft: String, review: String) {
            self.id = id
            self.task = task
            self.note = note
            self.draft = draft
            self.review = review
          }
        }
      }
      """
    }
  }

  @Test
  func includesAStoredPropertyWithObservers() {
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey var id: Int
        var task: String = "" {
          didSet { print(task) }
        }
        var count: Int {
          task.count
        }
      }
      """
    } expansion: {
      """
      struct Todo {
        @PrimaryKey var id: Int
        var task: String = "" {
          didSet { print(task) }
        }
        var count: Int {
          task.count
        }
      }

      extension Todo {
        static let relationName = "todos"

        static let schema = "public"

        static let selectString = "*"

        struct Columns: Sendable {
          let id = PostgrestColumn<Todo, Int>("id")
          let task = PostgrestColumn<Todo, String>("task")

          init() {
          }
        }

        static let columns = Columns()

        static let primaryKeyColumns: [String] = ["id"]

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
        }

        struct Draft: Encodable, Sendable {
          var id: Int
          var task: String

          enum CodingKeys: String, CodingKey {
            case id = "id"
            case task = "task"
          }

          init(id: Int, task: String) {
            self.id = id
            self.task = task
          }
        }
      }
      """
    }
  }

  @Test
  func draftCarriesACompoundPrimaryKey() {
    // A compound natural key is never database-generated, so the client is the only thing that can
    // supply it. Dropping it from `Draft` made the row impossible to create.
    assertMacro {
      """
      @Table("user_roles")
      struct UserRole {
        @PrimaryKey var userID: UUID
        @PrimaryKey var roleID: UUID
        var grantedAt: Date
      }
      """
    } expansion: {
      """
      struct UserRole {
        @PrimaryKey var userID: UUID
        @PrimaryKey var roleID: UUID
        var grantedAt: Date
      }

      extension UserRole {
        static let relationName = "user_roles"

        static let schema = "public"

        static let selectString = "*"

        struct Columns: Sendable {
          let userID = PostgrestColumn<UserRole, UUID>("user_id")
          let roleID = PostgrestColumn<UserRole, UUID>("role_id")
          let grantedAt = PostgrestColumn<UserRole, Date>("granted_at")

          init() {
          }
        }

        static let columns = Columns()

        static let primaryKeyColumns: [String] = ["user_id", "role_id"]

        enum CodingKeys: String, CodingKey {
          case userID = "user_id"
          case roleID = "role_id"
          case grantedAt = "granted_at"
        }

        struct Draft: Encodable, Sendable {
          var userID: UUID
          var roleID: UUID
          var grantedAt: Date

          enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case roleID = "role_id"
            case grantedAt = "granted_at"
          }

          init(userID: UUID, roleID: UUID, grantedAt: Date) {
            self.userID = userID
            self.roleID = roleID
            self.grantedAt = grantedAt
          }
        }
      }
      """
    }
  }

  @Test
  func draftOnATableThatIsNothingButACompoundKey() {
    // A pure join table previously expanded to `Draft` with no fields and an empty `init()`.
    // Neither half is `@Default`, so both are required: `Draft()` and `Draft(userID:)` do not
    // compile, and an incomplete key can no longer reach PostgREST as a 400.
    assertMacro {
      """
      @Table("user_roles")
      struct UserRole {
        @PrimaryKey var userID: UUID
        @PrimaryKey var roleID: UUID
      }
      """
    } expansion: {
      """
      struct UserRole {
        @PrimaryKey var userID: UUID
        @PrimaryKey var roleID: UUID
      }

      extension UserRole {
        static let relationName = "user_roles"

        static let schema = "public"

        static let selectString = "*"

        struct Columns: Sendable {
          let userID = PostgrestColumn<UserRole, UUID>("user_id")
          let roleID = PostgrestColumn<UserRole, UUID>("role_id")

          init() {
          }
        }

        static let columns = Columns()

        static let primaryKeyColumns: [String] = ["user_id", "role_id"]

        enum CodingKeys: String, CodingKey {
          case userID = "user_id"
          case roleID = "role_id"
        }

        struct Draft: Encodable, Sendable {
          var userID: UUID
          var roleID: UUID

          enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case roleID = "role_id"
          }

          init(userID: UUID, roleID: UUID) {
            self.userID = userID
            self.roleID = roleID
          }
        }
      }
      """
    }
  }
  /// `Int?` and `Optional<Int>` are the same type, and optionality has to be recognized in both
  /// spellings everywhere it is decided. The generated initializers used to give `= nil` only to
  /// the `?` form, so an `Optional<T>` column had to be passed explicitly — including in `Update`,
  /// whose whole contract is naming only what changes.
  @Test
  func acceptsTheOptionalSpellingOfAnOptional() {
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        @PrimaryKey @Default var id: Int
        var task: String
        var note: Optional<String>
        @Default var tag: Optional<String>
      }
      """
    } expansion: {
      """
      struct Todo {
        @PrimaryKey @Default var id: Int
        var task: String
        var note: Optional<String>
        @Default var tag: Optional<String>
      }

      extension Todo {
        static let relationName = "todos"

        static let schema = "public"

        static let selectString = "*"

        struct Columns: Sendable {
          let id = PostgrestColumn<Todo, Int>("id")
          let task = PostgrestColumn<Todo, String>("task")
          let note = PostgrestNullableColumn<Todo, String>("note")
          let tag = PostgrestNullableColumn<Todo, String>("tag")

          init() {
          }
        }

        static let columns = Columns()

        static let primaryKeyColumns: [String] = ["id"]

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
          case note = "note"
          case tag = "tag"
        }

        struct Draft: Encodable, Sendable {
          var id: Int?
          var task: String
          var note: Optional<String>
          var tag: Optional<String>

          enum CodingKeys: String, CodingKey {
            case id = "id"
            case task = "task"
            case note = "note"
            case tag = "tag"
          }

          init(id: Int? = nil, task: String, note: Optional<String> = nil, tag: Optional<String> = nil) {
            self.id = id
            self.task = task
            self.note = note
            self.tag = tag
          }
        }
      }
      """
    }
  }

  @Test
  func expandsAColumnsNamespace() {
    assertMacro {
      """
      @Table("todos")
      struct Todo {
        var id: Int
        @Column("due_at") var dueDate: Date?
      }
      """
    } expansion: {
      """
      struct Todo {
        var id: Int
        @Column("due_at") var dueDate: Date?
      }

      extension Todo {
        static let relationName = "todos"

        static let schema = "public"

        static let selectString = "*"

        struct Columns: Sendable {
          let id = PostgrestColumn<Todo, Int>("id")
          let dueDate = PostgrestNullableColumn<Todo, Date>("due_at")

          init() {
          }
        }

        static let columns = Columns()

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case dueDate = "due_at"
        }

        struct Draft: Encodable, Sendable {
          var id: Int
          var dueDate: Date?

          enum CodingKeys: String, CodingKey {
            case id = "id"
            case dueDate = "due_at"
          }

          init(id: Int, dueDate: Date? = nil) {
            self.id = id
            self.dueDate = dueDate
          }
        }
      }
      """
    }
  }
}
