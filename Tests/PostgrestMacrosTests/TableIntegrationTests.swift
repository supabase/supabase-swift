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
  // `@Default` is what makes the key optional in `Insert`, not `@PrimaryKey`. It says the database
  // generates this one — an identity column or a column with a default — matching what
  // `postgres-meta` reads to make a column optional for supabase-js.
  @PrimaryKey @Default var id: Int
  var task: String
  @Default var isDone: Bool
  @Column("due_at") var dueDate: Date?
}

// A compound natural key. Nothing in the database generates these, so neither half is `@Default`
// and both are required by `Insert` — an incomplete key is a compile error, and an `Insert` that
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
    let data = try JSONEncoder().encode(Todo.Insert(task: "buy milk", isDone: false))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"id\"") == false)
    #expect(json.contains("\"is_done\"") == true)
    #expect(json.contains("\"isDone\"") == false)
  }

  @Test
  func insertCarriesAPrimaryKeyTheClientSupplies() throws {
    let data = try JSONEncoder().encode(Todo.Insert(id: 7, task: "buy milk"))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"id\":7") == true)
  }

  @Test
  func insertCarriesAWholeCompoundPrimaryKey() throws {
    // The acceptance criterion for a join table: both halves of the key reach the wire, so the row
    // can actually be created.
    //
    // Both are also *required*, because neither is `@Default`. `IntegrationUserRole.Insert()` and
    // `.Insert(userID: 1)` no longer compile, which is the point — before, they compiled and sent
    // an incomplete body for PostgREST to reject at runtime. Swift cannot assert that something
    // fails to compile, so this notes it rather than covering it.
    let data = try JSONEncoder().encode(IntegrationUserRole.Insert(userID: 1, roleID: 2))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"user_id\":1") == true)
    #expect(json.contains("\"role_id\":2") == true)
  }

  @Test
  func anOptionalSpelledColumnCanBeOmitted() throws {
    // This is the assertion the expansion test cannot make: `MacroTesting` compares generated
    // text, it does not compile it. Both calls omit `tag`, which only compiles if the generated
    // initializers defaulted an `Optional<String>` to nil.
    let insert = try JSONEncoder().encode(IntegrationNote.Insert(body: "hello"))
    #expect(String(decoding: insert, as: UTF8.self) == #"{"body":"hello"}"#)

    // `Update()` naming nothing at all is the stronger half — a partial update was impossible on
    // such a table before, because every `Optional<T>` column had to be passed.
    let update = try JSONEncoder().encode(IntegrationNote.Update())
    #expect(String(decoding: update, as: UTF8.self) == "{}")
  }

  @Test
  func aNilOptionalIsOmittedSoTheDatabaseDefaultApplies() throws {
    // `@Default var isDone` is optional in `Insert` precisely so it can be left out. Encoding it
    // as `null` would insert NULL instead of letting the column default apply.
    let data = try JSONEncoder().encode(Todo.Insert(task: "buy milk"))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json == #"{"task":"buy milk"}"#)
  }

  @Test
  func aPartialUpdateNamesOnlyWhatItChanges() throws {
    let data = try JSONEncoder().encode(Todo.Update(isDone: true))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json == #"{"is_done":true}"#)
  }

  @Test
  func aMacroTypeFlowsThroughTheTypedQuery() async throws {
    let capture = RequestCapture(
      body: #"[{"id":1,"task":"buy milk","is_done":false,"due_at":null}]"#
    )
    let todos = try await capture.client
      .from(Todo.self)
      .select()
      .eq(\.isDone, false)
      .order(\.id, ascending: false)
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
      .insert(Todo.Insert(task: "buy milk"))
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
      .eq(\.task, "buy milk")
      .execute()
      .value

    #expect(rows.count == 1)
    #expect(capture.path?.hasSuffix("/active_todos") == true)
    #expect(capture.query?.contains("task=eq.buy milk") == true)
  }

  @Test
  func aTypedUpsertCarriesTheConflictKey() async throws {
    // `upsert` sends no `on_conflict`, so PostgREST resolves against the primary key — which has
    // to be in the body for that to mean anything. While `Insert` dropped the key, the merge half
    // of every upsert was unreachable and each call just inserted another row.
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .upsert(Todo.Insert(id: 1, task: "buy milk"))
      .execute()

    #expect(capture.path?.hasSuffix("/todos") == true)
    #expect(capture.bodyString?.contains(#""id":1"#) == true)
  }

  @Test
  func updateCanChangeAKeyColumn() async throws {
    // Renaming a natural key is a real operation. Targeting is a separate concern — the filter
    // below is what picks the row — so keeping the key out of the payload only removed the
    // ability to change it.
    let capture = RequestCapture()
    _ = try await capture.client
      .from(IntegrationUserRole.self)
      .update(IntegrationUserRole.Update(roleID: 3))
      .eq(\.userID, 1)
      .execute()

    #expect(capture.bodyString == #"{"role_id":3}"#)
  }

  @Test
  func updateStillOmitsAKeyItIsNotChanging() async throws {
    // The addition is purely additive: a caller that does not name the key is unaffected.
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .update(Todo.Update(task: "buy oat milk"))
      .eq(\.id, 1)
      .execute()

    #expect(capture.bodyString == #"{"task":"buy oat milk"}"#)
  }
}
