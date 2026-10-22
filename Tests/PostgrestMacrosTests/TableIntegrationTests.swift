//
//  TableIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation
@_spi(Experimental) import PostgrestMacros
import Testing

@Table("todos")
struct IntegrationTodo: Hashable {
  @PrimaryKey @Default var id: Int
  var task: String
  @Default var isDone: Bool
  @Column("due_at") var dueDate: Date?
}

@Table("user_roles")
struct IntegrationUserRole {
  @PrimaryKey var userID: Int
  @PrimaryKey var roleID: Int
  var grantedAt: Date?
}

@Table("notes")
struct IntegrationNote {
  @PrimaryKey @Default var id: Int
  var body: String
  var tag: Optional<String>  // swiftlint:disable:this syntactic_sugar
}

@Table("counters")
struct IntegrationCounter {
  @PrimaryKey @Generated var id: Int
  var count: Int
  @Generated var updatedAt: Date?
}

@Table("audit_events")
struct IntegrationAuditEvent {
  var action: String
  var recordedBy: String
}

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

enum _PublicSchema {}

enum PublicSchema {}

enum IntegrationPrivateSchema: _PostgrestSchema {
  static let name = "private"
}

@Table("secrets", schema: IntegrationPrivateSchema.self)
struct IntegrationSecret {
  var id: Int
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
  func macroSuppliesTheSchemaType() {
    #expect(Todo.Schema.self == PostgREST._PublicSchema.self)
    #expect(IntegrationSecret.Schema.self == IntegrationPrivateSchema.self)
    #expect(IntegrationSecret.schema == "private")
  }

  @Test
  func theGeneratedNamespaceCarriesNamesAndTypes() {
    #expect(Todo.columns.task.postgrestExpression == "task")
    #expect(Todo.columns.isDone.postgrestExpression == "is_done")
    #expect(Todo.columns.dueDate.postgrestExpression == "due_at")
    #expect(type(of: Todo.columns.isDone).Value.self == Bool.self)
    #expect(type(of: Todo.columns.dueDate).Value.self == Date.self)
  }

  @Test
  func anImplicitlyUnwrappedOptionalIsANullableColumn() {
    #expect(IntegrationDraftNote.columns.title.postgrestExpression == "title")
    #expect(type(of: IntegrationDraftNote.columns.title).Value.self == String.self)
    _ = IntegrationDraftNote.columns.title.isNull()
    _ = IntegrationDraftNote.Draft(title: nil)
  }

  @Test
  func insertOmitsANilPrimaryKeyAndUsesColumnNames() throws {
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
    let data = try JSONEncoder().encode(IntegrationUserRole.Draft(userID: 1, roleID: 2))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"user_id\":1") == true)
    #expect(json.contains("\"role_id\":2") == true)
  }

  @Test
  func aGeneratedColumnNeverReachesAWriteBody() async throws {
    let capture = RequestCapture()
    _ = try await capture.client.from(IntegrationCounter.self)
      .insert(IntegrationCounter.Draft(count: 1)).execute()
    #expect(capture.bodyString == #"{"count":1}"#)

    let update = RequestCapture()
    _ = try await update.client.from(IntegrationCounter.self)
      .update { $0.count = 2 }.where { $0.id.eq(1) }.execute()
    #expect(update.bodyString == #"{"count":2}"#)
    #expect(update.query?.contains("id=eq.1") == true)
  }

  @Test
  func aGeneratedColumnStillReadsFiltersAndOrders() async throws {
    #expect(IntegrationCounter.primaryKeyColumns == ["id"])
    #expect(IntegrationCounter.columns.id.postgrestExpression == "id")
    #expect(IntegrationCounter.columns.updatedAt.postgrestExpression == "updated_at")

    let capture = RequestCapture(body: #"[{"id":1,"count":3,"updated_at":null}]"#)
    let rows = try await capture.client.from(IntegrationCounter.self).select()
      .where { $0.updatedAt.isNull() && $0.id.gt(0) }
      .order { $0.id.desc() }
      .execute().value
    #expect(capture.query?.contains("updated_at=is.null") == true)
    #expect(capture.query?.contains("id=gt.0") == true)
    #expect(capture.query?.contains("order=id.desc") == true)
    #expect(rows.first?.id == 1)
    #expect(rows.first?.count == 3)
  }

  @Test
  func macroReportsThePrimaryKeyColumns() {
    #expect(Todo.primaryKeyColumns == ["id"])
    #expect(IntegrationUserRole.primaryKeyColumns == ["user_id", "role_id"])
  }

  @Test
  func onlyARelationWithADeclaredKeyIsKeyed() {
    #expect(Todo.self is any _PostgrestKeyedRelation.Type)
    #expect(IntegrationUserRole.self is any _PostgrestKeyedRelation.Type)
    #expect(!(IntegrationAuditEvent.self is any _PostgrestKeyedRelation.Type))
    #expect(!(IntegrationActiveTodo.self is any _PostgrestKeyedRelation.Type))
  }

  @Test
  func aKeylessRelationCanStillUpsertOnAnExplicitTarget() async throws {
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
    let insert = try JSONEncoder().encode(IntegrationNote.Draft(body: "hello"))
    #expect(String(decoding: insert, as: UTF8.self) == #"{"body":"hello"}"#)
  }

  @Test
  func aNilOptionalIsOmittedSoTheDatabaseDefaultApplies() throws {
    let data = try JSONEncoder().encode(Todo.Draft(task: "buy milk"))
    let json = String(decoding: data, as: UTF8.self)
    #expect(json == #"{"task":"buy milk"}"#)
  }

  @Test
  func aPartialUpdateNamesOnlyWhatItChanges() throws {
    let data = try JSONEncoder().encode(_PostgrestUpdate<Todo> { $0.isDone = true })
    let json = String(decoding: data, as: UTF8.self)
    #expect(json == #"{"is_done":true}"#)
  }

  @Test
  func aMacroTypeCanClearANullableColumn() async throws {
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
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .upsert(Todo.Draft(id: 1, task: "buy milk"))
      .execute()

    #expect(capture.path?.hasSuffix("/todos") == true)
    #expect(capture.bodyString?.contains(#""id":1"#) == true)
  }

  @Test
  func aTypedUpsertReturningKeepsTheConflictResolutionPreference() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .upsert(Todo.Draft(id: 1, task: "buy milk"))
      .returning()
      .execute()

    #expect(capture.prefer == "resolution=merge-duplicates,return=representation")
  }

  @Test
  func aTypedUpsertExecuteAloneKeepsAMinimalReturnPreference() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .upsert(Todo.Draft(id: 1, task: "buy milk"))
      .execute()

    #expect(capture.prefer == "resolution=merge-duplicates,return=minimal")
  }

  @Test
  func aTypedInsertReturningSendsExactlyOneReturnPreference() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .insert(Todo.Draft(task: "buy milk"))
      .returning()
      .execute()

    #expect(capture.prefer == "return=representation")
  }

  @Test
  func aTypedUpsertCanIgnoreDuplicatesInsteadOfMergingThem() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .upsert(Todo.Draft(id: 1, task: "buy milk"), resolution: .ignoreDuplicates)
      .execute()

    #expect(capture.prefer == "resolution=ignore-duplicates,return=minimal")
    #expect(capture.query?.contains("on_conflict=id") == true)
  }

  @Test
  func anIgnoreDuplicatesResolutionSurvivesReturning() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .upsert(Todo.Draft(id: 1, task: "buy milk"), resolution: .ignoreDuplicates)
      .returning()
      .execute()

    #expect(capture.prefer == "resolution=ignore-duplicates,return=representation")
  }

  @Test
  func anExplicitConflictTargetTakesAResolution() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(IntegrationNote.self)
      .upsert(
        IntegrationNote.Draft(body: "remember the milk", tag: "home"),
        onConflict: \.tag,
        resolution: .ignoreDuplicates
      )
      .execute()

    #expect(capture.prefer == "resolution=ignore-duplicates,return=minimal")
    #expect(capture.query?.contains("on_conflict=tag") == true)
  }

  @Test
  func aBulkUpsertTakesAResolutionOnEitherConflictTarget() async throws {
    let derived = RequestCapture()
    _ = try await derived.client
      .from(Todo.self)
      .upsert(
        [Todo.Draft(id: 1, task: "buy milk"), Todo.Draft(id: 2, task: "buy bread")],
        resolution: .ignoreDuplicates
      )
      .execute()

    #expect(derived.prefer == "resolution=ignore-duplicates,return=minimal")

    let explicit = RequestCapture()
    _ = try await explicit.client
      .from(IntegrationNote.self)
      .upsert(
        [IntegrationNote.Draft(body: "remember the milk", tag: "home")],
        onConflict: \.tag,
        resolution: .ignoreDuplicates
      )
      .execute()

    #expect(explicit.prefer == "resolution=ignore-duplicates,return=minimal")
  }

  @Test
  func aTypedUpsertDerivesTheConflictTargetFromTheKey() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .upsert(Todo.Draft(id: 1, task: "buy milk"))
      .execute()

    #expect(capture.query?.contains("on_conflict=id") == true)
  }

  @Test
  func aTypedUpsertDerivesACompoundConflictTarget() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(IntegrationUserRole.self)
      .upsert(IntegrationUserRole.Draft(userID: 1, roleID: 2))
      .execute()

    #expect(capture.query?.contains("on_conflict=user_id,role_id") == true)
  }

  @Test
  func aTypedUpsertTakesAnExplicitConflictTarget() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(IntegrationNote.self)
      .upsert(IntegrationNote.Draft(body: "remember the milk", tag: "home"), onConflict: \.tag)
      .execute()

    #expect(capture.query?.contains("on_conflict=tag") == true)
  }

  @Test
  func anExplicitConflictTargetMapsEveryColumnName() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .upsert(Todo.Draft(task: "buy milk"), onConflict: \.task, \.isDone)
      .execute()

    #expect(capture.query?.contains("on_conflict=task,is_done") == true)
  }

  @Test
  func updateCanChangeAKeyColumn() async throws {
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
    let capture = RequestCapture()
    _ = try await capture.client
      .from(Todo.self)
      .update { $0.task = "buy oat milk" }
      .where { $0.id.eq(1) }
      .execute()

    #expect(capture.bodyString == #"{"task":"buy oat milk"}"#)
  }
}
