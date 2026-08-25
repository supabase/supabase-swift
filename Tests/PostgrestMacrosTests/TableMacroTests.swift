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
  /// A generated surrogate key: `@Default` is what makes it optional in `Insert`, not
  /// `@PrimaryKey`. See `insertOnATableThatIsNothingButACompoundKey` for a key without it.
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
      #"""
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

        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.id:
            return "id"
          case \Self.task:
            return "task"
          case \Self.isDone:
            return "is_done"
          case \Self.dueDate:
            return "due_at"
          default:
            fatalError("Todo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
          case isDone = "is_done"
          case dueDate = "due_at"
        }

        struct Insert: Encodable, Sendable {
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

        struct Update: Encodable, Sendable {
          var task: String?
          var isDone: Bool?
          var dueDate: Date?

          enum CodingKeys: String, CodingKey {
            case task = "task"
            case isDone = "is_done"
            case dueDate = "due_at"
          }

          init(task: String? = nil, isDone: Bool? = nil, dueDate: Date? = nil) {
            self.task = task
            self.isDone = isDone
            self.dueDate = dueDate
          }
        }
      }
      """#
    }
  }

  @Test
  func readOnlyTableOmitsInsertAndUpdate() {
    assertMacro {
      """
      @Table("active_todos", readOnly: true)
      struct ActiveTodo {
        var id: Int
      }
      """
    } expansion: {
      #"""
      struct ActiveTodo {
        var id: Int
      }

      extension ActiveTodo {
        static let relationName = "active_todos"

        static let schema = "public"

        static let selectString = "*"

        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.id:
            return "id"
          default:
            fatalError("ActiveTodo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case id = "id"
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
      #"""
      public struct Todo {
        @PrimaryKey var id: Int
        var task: String
      }

      extension Todo {
        public static let relationName = "todos"

        public static let schema = "app"

        public static let selectString = "*"

        public static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.id:
            return "id"
          case \Self.task:
            return "task"
          default:
            fatalError("Todo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
        }

        public struct Insert: Encodable, Sendable {
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

        public struct Update: Encodable, Sendable {
          public var task: String?

          enum CodingKeys: String, CodingKey {
            case task = "task"
          }

          public init(task: String? = nil) {
            self.task = task
          }
        }
      }
      """#
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
      #"""
      struct Todo {
        static let table = "todos"
        var htmlURL: String
        var summary: String { htmlURL }
      }

      extension Todo {
        static let relationName = "todos"

        static let schema = "public"

        static let selectString = "*"

        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.htmlURL:
            return "html_url"
          default:
            fatalError("Todo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case htmlURL = "html_url"
        }

        struct Insert: Encodable, Sendable {
          var htmlURL: String

          enum CodingKeys: String, CodingKey {
            case htmlURL = "html_url"
          }

          init(htmlURL: String) {
            self.htmlURL = htmlURL
          }
        }

        struct Update: Encodable, Sendable {
          var htmlURL: String?

          enum CodingKeys: String, CodingKey {
            case htmlURL = "html_url"
          }

          init(htmlURL: String? = nil) {
            self.htmlURL = htmlURL
          }
        }
      }
      """#
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
      #"""
      struct Todo {
        @PrimaryKey var id: Int
        var task: String, note: String
        var draft, review: String
      }

      extension Todo {
        static let relationName = "todos"

        static let schema = "public"

        static let selectString = "*"

        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.id:
            return "id"
          case \Self.task:
            return "task"
          case \Self.note:
            return "note"
          case \Self.draft:
            return "draft"
          case \Self.review:
            return "review"
          default:
            fatalError("Todo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
          case note = "note"
          case draft = "draft"
          case review = "review"
        }

        struct Insert: Encodable, Sendable {
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

        struct Update: Encodable, Sendable {
          var task: String?
          var note: String?
          var draft: String?
          var review: String?

          enum CodingKeys: String, CodingKey {
            case task = "task"
            case note = "note"
            case draft = "draft"
            case review = "review"
          }

          init(task: String? = nil, note: String? = nil, draft: String? = nil, review: String? = nil) {
            self.task = task
            self.note = note
            self.draft = draft
            self.review = review
          }
        }
      }
      """#
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
      #"""
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

        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.id:
            return "id"
          case \Self.task:
            return "task"
          default:
            fatalError("Todo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
        }

        struct Insert: Encodable, Sendable {
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

        struct Update: Encodable, Sendable {
          var task: String?

          enum CodingKeys: String, CodingKey {
            case task = "task"
          }

          init(task: String? = nil) {
            self.task = task
          }
        }
      }
      """#
    }
  }

  @Test
  func insertCarriesACompoundPrimaryKey() {
    // A compound natural key is never database-generated, so the client is the only thing that can
    // supply it. Dropping it from `Insert` made the row impossible to create.
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
      #"""
      struct UserRole {
        @PrimaryKey var userID: UUID
        @PrimaryKey var roleID: UUID
        var grantedAt: Date
      }

      extension UserRole {
        static let relationName = "user_roles"

        static let schema = "public"

        static let selectString = "*"

        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.userID:
            return "user_id"
          case \Self.roleID:
            return "role_id"
          case \Self.grantedAt:
            return "granted_at"
          default:
            fatalError("UserRole: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case userID = "user_id"
          case roleID = "role_id"
          case grantedAt = "granted_at"
        }

        struct Insert: Encodable, Sendable {
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

        struct Update: Encodable, Sendable {
          var grantedAt: Date?

          enum CodingKeys: String, CodingKey {
            case grantedAt = "granted_at"
          }

          init(grantedAt: Date? = nil) {
            self.grantedAt = grantedAt
          }
        }
      }
      """#
    }
  }

  @Test
  func insertOnATableThatIsNothingButACompoundKey() {
    // A pure join table previously expanded to `Insert` with no fields and an empty `init()`.
    // Neither half is `@Default`, so both are required: `Insert()` and `Insert(userID:)` do not
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
      #"""
      struct UserRole {
        @PrimaryKey var userID: UUID
        @PrimaryKey var roleID: UUID
      }

      extension UserRole {
        static let relationName = "user_roles"

        static let schema = "public"

        static let selectString = "*"

        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.userID:
            return "user_id"
          case \Self.roleID:
            return "role_id"
          default:
            fatalError("UserRole: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case userID = "user_id"
          case roleID = "role_id"
        }

        struct Insert: Encodable, Sendable {
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

        struct Update: Encodable, Sendable {

          init() {
          }
        }
      }
      """#
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
      #"""
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

        static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
          switch keyPath {
          case \Self.id:
            return "id"
          case \Self.task:
            return "task"
          case \Self.note:
            return "note"
          case \Self.tag:
            return "tag"
          default:
            fatalError("Todo: no column is mapped for that key path")
          }
        }

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
          case note = "note"
          case tag = "tag"
        }

        struct Insert: Encodable, Sendable {
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

        struct Update: Encodable, Sendable {
          var task: String?
          var note: Optional<String>
          var tag: Optional<String>

          enum CodingKeys: String, CodingKey {
            case task = "task"
            case note = "note"
            case tag = "tag"
          }

          init(task: String? = nil, note: Optional<String> = nil, tag: Optional<String> = nil) {
            self.task = task
            self.note = note
            self.tag = tag
          }
        }
      }
      """#
    }
  }

}
