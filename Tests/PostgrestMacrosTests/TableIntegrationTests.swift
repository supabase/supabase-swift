//
//  TableIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation
import PostgrestMacros
import Testing

// Declared at file scope on purpose. `@Table` attaches an extension, and Swift does not allow an
// extension of a type nested inside another type, so annotating a nested struct fails to compile.
@Table("todos")
struct IntegrationTodo: Hashable {
  // `@Default` is what makes the key optional in `Draft`, not `@PrimaryKey`. It says the database
  // generates this one — an identity column or a column with a default — matching what
  // `postgres-meta` reads to make a column optional for supabase-js.
  @PrimaryKey @Default var id: Int
  var task: String
  @Default var isDone: Bool
  @Column("due_at") var dueDate: Date?
}

// A compound natural key. Nothing in the database generates these, so neither half is `@Default`
// and both are required by `Draft` — an incomplete key is a compile error, and a `Draft` that
// dropped them made the table impossible to write to at all.
@Table("user_roles")
struct IntegrationUserRole {
  @PrimaryKey var userID: Int
  @PrimaryKey var roleID: Int
  var grantedAt: Date?
}

// `Optional<T>` rather than `T?`, to keep the generated defaults honest for both spellings.
@Table("notes")
struct IntegrationNote {
  @PrimaryKey @Default var id: Int
  var body: String
  var tag: Optional<String>
}

// A writable table with no declared key — an append-only log. It must not conform to
// `PostgrestKeyedRelation`, so the derived-target `upsert` is simply not available on it: there is
// no key for PostgREST to merge on, and the call would quietly insert another row every time.
@Table("audit_events")
struct IntegrationAuditEvent {
  var action: String
  var recordedBy: String
}

// An implicitly unwrapped optional. The spelling means the same nullable column as `T?`, and it
// only ever reached a property type before `Columns` existed — a generic argument rejects `!`, so
// the compile error landed on expanded code the author never wrote.
@Table("drafts")
struct IntegrationDraftNote {
  @PrimaryKey @Default var id: Int
  var title: String!
}

@Table("active_todos", readOnly: true)
struct IntegrationActiveTodo {
  var id: Int
  var task: String
}

@Suite
struct TableIntegrationTests {
  typealias Todo = IntegrationTodo

  @Test
  func macroSuppliesTheRelationName() {
    #expect(Todo.relationName == "todos")
    #expect(Todo.schema == "public")
    #expect(Todo.selectString == "*")
  }

  /// `assertMacro` checks the emitted text. This checks the expansion compiles into usable
  /// values on a real type, which the text alone does not prove.
  @Test
  func theGeneratedNamespaceCarriesNamesAndTypes() {
    #expect(Todo.columns.task.postgrestExpression == "task")
    #expect(Todo.columns.isDone.postgrestExpression == "is_done")
    #expect(Todo.columns.dueDate.postgrestExpression == "due_at")
    #expect(type(of: Todo.columns.isDone).Value.self == Bool.self)
    // The nullable column carries the wrapped type.
    #expect(type(of: Todo.columns.dueDate).Value.self == Date.self)
  }

  /// An implicitly unwrapped optional is a nullable column: the wrapped type reaches `Value`, so
  /// the operators are there, and `isNull()` is too.
  @Test
  func anImplicitlyUnwrappedOptionalIsANullableColumn() {
    #expect(IntegrationDraftNote.columns.title.postgrestExpression == "title")
    #expect(type(of: IntegrationDraftNote.columns.title).Value.self == String.self)
    _ = IntegrationDraftNote.columns.title.isNull()
    _ = IntegrationDraftNote.Draft(title: nil)
  }

  @Test
  func macroMapsKeyPathsToColumns() {
    #expect(Todo.columnName(for: \.id) == "id")
    #expect(Todo.columnName(for: \.isDone) == "is_done")
    #expect(Todo.columnName(for: \.dueDate) == "due_at")
  }

  @Test
  func insertOmitsANilPrimaryKeyAndUsesColumnNames() throws {
    // The key is optional rather than absent, so leaving it out still lets the database fill it in.
    // Optional because it is `@Default`, not because it is the key.
    let data = try JSONEncoder().encode(Todo.Draft(task: "buy milk", isDone: false))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"id\"") == false)
    #expect(json.contains("\"is_done\"") == true)
    #expect(json.contains("\"isDone\"") == false)
  }

  @Test
  func insertCarriesAPrimaryKeyTheClientSupplies() throws {
    let data = try JSONEncoder().encode(Todo.Draft(id: 7, task: "buy milk"))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"id\":7") == true)
  }

  @Test
  func insertCarriesAWholeCompoundPrimaryKey() throws {
    // The acceptance criterion for a join table: both halves of the key reach the wire, so the row
    // can actually be created.
    //
    // Both are also *required*, because neither is `@Default`. `IntegrationUserRole.Draft()` and
    // `.Draft(userID: 1)` no longer compile, which is the point — before, they compiled and sent
    // an incomplete body for PostgREST to reject at runtime. Swift cannot assert that something
    // fails to compile, so this notes it rather than covering it.
    let data = try JSONEncoder().encode(IntegrationUserRole.Draft(userID: 1, roleID: 2))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"user_id\":1") == true)
    #expect(json.contains("\"role_id\":2") == true)
  }

  @Test
  func macroReportsThePrimaryKeyColumns() {
    // The only thing `@PrimaryKey` produces now that it no longer gates `Draft` optionality or
    // filters `Update`. Declaration order, and column names rather than property names.
    #expect(Todo.primaryKeyColumns == ["id"])
    #expect(IntegrationUserRole.primaryKeyColumns == ["user_id", "role_id"])
  }

  @Test
  func onlyARelationWithADeclaredKeyIsKeyed() {
    // The conformance *is* the mechanism. `primaryKeyColumns` is mandatory on
    // `PostgrestKeyedRelation`, so "no key" is a missing conformance rather than an empty array —
    // and an empty `on_conflict`, which is a different request, stops being representable.
    #expect(Todo.self is any PostgrestKeyedRelation.Type)
    #expect(IntegrationUserRole.self is any PostgrestKeyedRelation.Type)
    #expect(!(IntegrationAuditEvent.self is any PostgrestKeyedRelation.Type))
    #expect(!(IntegrationActiveTodo.self is any PostgrestKeyedRelation.Type))
  }

  @Test
  func aKeylessRelationCanStillUpsertOnAnExplicitTarget() async throws {
    // Losing the derived overload must not cost the keyless relation the operation itself. A
    // unique constraint it does have is still a legal target.
    let capture = RequestCapture()
    _ = try await capture.client
      .from(IntegrationAuditEvent.self)
      .upsert(
        IntegrationAuditEvent.Draft(action: "sign_in", recordedBy: "service_role"),
        onConflict: \.action
      )
      .execute()

    #expect(capture.query?.contains("on_conflict=action") == true)
  }

  @Test
  func anOptionalSpelledColumnCanBeOmitted() throws {
    // This is the assertion the expansion test cannot make: `MacroTesting` compares generated
    // text, it does not compile it. The call omits `tag`, which only compiles if the generated
    // initializer defaulted an `Optional<String>` to nil.
    let insert = try JSONEncoder().encode(IntegrationNote.Draft(body: "hello"))
    #expect(String(decoding: insert, as: UTF8.self) == #"{"body":"hello"}"#)
  }

  @Test
  func aNilOptionalIsOmittedSoTheDatabaseDefaultApplies() throws {
    // `@Default var isDone` is optional in `Draft` precisely so it can be left out. Encoding it
    // as `null` would insert NULL instead of letting the column default apply.
    let data = try JSONEncoder().encode(Todo.Draft(task: "buy milk"))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json == #"{"task":"buy milk"}"#)
  }

  @Test
  func aPartialUpdateNamesOnlyWhatItChanges() throws {
    let data = try JSONEncoder().encode(PostgrestUpdate<Todo> { $0.isDone = true })
    let json = String(decoding: data, as: UTF8.self)
    #expect(json == #"{"is_done":true}"#)
  }

  @Test
  func aMacroTypeCanClearANullableColumn() async throws {
    // SDK-1610. `due_at` is nullable, so `nil` has to reach the wire as an explicit null rather
    // than dropping the key, which is what "leave this column alone" means.
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .update { $0.dueDate = nil }
      .where { $0.id.eq(1) }
      .execute()

    #expect(capture.bodyString == #"{"due_at":null}"#)
  }

  @Test
  func aMacroTypeFlowsThroughTheTypedQuery() async throws {
    let capture = RequestCapture(
      body: #"[{"id":1,"task":"buy milk","is_done":false,"due_at":null}]"#
    )
    let todos = try await capture.client
      .from(Todo.self)
      .select()
      .where { $0.isDone.eq(false) }
      .order { $0.id.desc() }
      .execute()
      .value

    #expect(todos == [Todo(id: 1, task: "buy milk", isDone: false, dueDate: nil)])
    #expect(capture.path?.hasSuffix("/todos") == true)
    #expect(capture.query?.contains("select=*") == true)
    #expect(capture.query?.contains("is_done=eq.false") == true)
    #expect(capture.query?.contains("id.desc") == true)
  }

  @Test
  func aMacroTypeFlowsThroughATypedWrite() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .insert(Todo.Draft(task: "buy milk"))
      .execute()

    #expect(capture.path?.hasSuffix("/todos") == true)
    #expect(capture.bodyString == #"{"task":"buy milk"}"#)
  }

  @Test
  func aReadOnlyRelationIsStillQueryable() async throws {
    let capture = RequestCapture(body: #"[{"id":1,"task":"buy milk"}]"#)
    let rows = try await capture.client
      .from(IntegrationActiveTodo.self)
      .select()
      .where { $0.task.eq("buy milk") }
      .execute()
      .value

    #expect(rows.count == 1)
    #expect(capture.path?.hasSuffix("/active_todos") == true)
    #expect(capture.query?.contains("task=eq.buy milk") == true)
  }

  @Test
  func aTypedUpsertCarriesTheConflictKey() async throws {
    // The conflict target only means something if the columns it names are in the body. While
    // `Draft` dropped the key, the merge half of every upsert was unreachable and each call just
    // inserted another row.
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .upsert(Todo.Draft(id: 1, task: "buy milk"))
      .execute()

    #expect(capture.path?.hasSuffix("/todos") == true)
    #expect(capture.bodyString?.contains(#""id":1"#) == true)
  }

  @Test
  func aTypedUpsertDerivesTheConflictTargetFromTheKey() async throws {
    // PostgREST resolves an absent `on_conflict` against the primary key already, so this is the
    // same request either way. Naming it is what makes the request say what it merges on, and it
    // is only reachable because the relation declares a key — a keyless one has no such overload.
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .upsert(Todo.Draft(id: 1, task: "buy milk"))
      .execute()

    #expect(capture.query?.contains("on_conflict=id") == true)
  }

  @Test
  func aTypedUpsertDerivesACompoundConflictTarget() async throws {
    // A join table conflicts on both halves of its key, in declaration order.
    let capture = RequestCapture()
    _ = try await capture.client
      .from(IntegrationUserRole.self)
      .upsert(IntegrationUserRole.Draft(userID: 1, roleID: 2))
      .execute()

    #expect(capture.query?.contains("on_conflict=user_id,role_id") == true)
  }

  @Test
  func aTypedUpsertTakesAnExplicitConflictTarget() async throws {
    // Merging on a unique constraint that is not the primary key is the reason the override
    // exists. Spelled as a key path, so a column that does not exist is a compile error rather
    // than a PostgREST 400.
    let capture = RequestCapture()
    _ = try await capture.client
      .from(IntegrationNote.self)
      .upsert(IntegrationNote.Draft(body: "remember the milk", tag: "home"), onConflict: \.tag)
      .execute()

    #expect(capture.query?.contains("on_conflict=tag") == true)
  }

  @Test
  func anExplicitConflictTargetMapsEveryColumnName() async throws {
    // `isDone` has to reach the wire as `is_done`, so the override goes through the same
    // `columnName(for:)` mapping every filter uses rather than interpolating property names.
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .upsert(Todo.Draft(task: "buy milk"), onConflict: \.task, \.isDone)
      .execute()

    #expect(capture.query?.contains("on_conflict=task,is_done") == true)
  }

  @Test
  func updateCanChangeAKeyColumn() async throws {
    // Renaming a natural key is a real operation. Targeting is a separate concern — the filter
    // below is what picks the row — so keeping the key out of the payload only removed the
    // ability to change it.
    let capture = RequestCapture()
    _ = try await capture.client
      .from(IntegrationUserRole.self)
      .update { $0.roleID = 3 }
      .where { $0.userID.eq(1) }
      .execute()

    #expect(capture.bodyString == #"{"role_id":3}"#)
  }

  @Test
  func updateStillOmitsAKeyItIsNotChanging() async throws {
    // The addition is purely additive: a caller that does not name the key is unaffected.
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .update { $0.task = "buy oat milk" }
      .where { $0.id.eq(1) }
      .execute()

    #expect(capture.bodyString == #"{"task":"buy oat milk"}"#)
  }
}
