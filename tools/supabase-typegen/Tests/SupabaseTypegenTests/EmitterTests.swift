//
//  EmitterTests.swift
//  SupabaseTypegenTests
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation

import Testing

@testable import SupabaseTypegen

/// One generator run whose output is compared with a committed golden file.
///
/// Rewrite the golden files with `SUPABASE_TYPEGEN_RECORD=1 swift test --filter EmitterTests`.
struct GoldenCase: CustomTestStringConvertible, Sendable {
  var fixture: String
  var arguments: [String]
  /// The golden file, relative to the repository root.
  var golden: String

  var schemas: [String] {
    zip(arguments, arguments.dropFirst()).filter { $0.0 == "--schema" }.map(\.1)
  }

  var testDescription: String { golden }

  /// `#filePath` is `tools/supabase-typegen/Tests/SupabaseTypegenTests/EmitterTests.swift`.
  var url: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("../../../../\(golden)")
      .standardized
  }

  static let integration = GoldenCase(
    fixture: "generator_metadata",
    arguments: [],
    golden: "tools/supabase-typegen/Tests/SupabaseTypegenTests/__Goldens__/"
      + "generator_metadata.swift.golden"
  )

  // The goldens below are the sources of test targets in the root package, so `swift build
  // --build-tests` there compiles them against `PostgrestMacros`. Each fixture needs its own
  // target: they declare types with the same names.
  static let integrationPublic = GoldenCase(
    fixture: "generator_metadata",
    arguments: ["--access-control", "public"],
    golden: "Tests/SupabaseTypegenOutputTests/Generated.swift"
  )

  static let postgrestTypegen = GoldenCase(
    fixture: "postgrest_typegen_metadata",
    arguments: ["--access-control", "public"],
    golden: "Tests/SupabaseTypegenPostgrestTypegenOutputTests/Generated.swift"
  )

  // Without `inventory`, whose `books` clashes with `public.inventory_books`.
  static let hostile = GoldenCase(
    fixture: "hostile_metadata",
    arguments: [
      "--access-control", "public", "--schema", "public", "--schema", #"my"schema"#,
      "--schema", "date",
    ],
    golden: "Tests/SupabaseTypegenHostileOutputTests/Generated.swift"
  )

  static let all = [integration, integrationPublic, postgrestTypegen, hostile]
}

@Suite
struct EmitterTests {
  @Test(arguments: GoldenCase.all)
  func outputMatchesTheGoldenFile(_ golden: GoldenCase) throws {
    let result = run(arguments: golden.arguments) { Fixture.data(golden.fixture) }
    #expect(result.exitCode == 0, "\(result.standardError)")

    if ProcessInfo.processInfo.environment["SUPABASE_TYPEGEN_RECORD"] == "1" {
      try Data(result.standardOutput.utf8).write(to: golden.url)
      Issue.record("Recorded \(golden.golden); run again without SUPABASE_TYPEGEN_RECORD")
      return
    }
    let expected = try String(contentsOf: golden.url, encoding: .utf8)
    #expect(
      result.standardOutput == expected,
      "Output differs from \(golden.golden); record with SUPABASE_TYPEGEN_RECORD=1"
    )
  }

  /// `@Column` is emitted exactly when `@Table`'s own conversion of the Swift name, backticks
  /// included, does not give back the column name. `camelToSnakeCase` is the macro's source,
  /// compiled in through the `CamelToSnake.swift` symlink.
  @Test(arguments: GoldenCase.all)
  func columnAttributeFollowsTheMacroConversion(_ golden: GoldenCase) throws {
    let model = DatabaseModel(
      try decodeGeneratorMetadata(Fixture.data(golden.fixture)), schemas: golden.schemas)
    let properties = try FilePlan(model).relations.flatMap(\.properties)
    #expect(!properties.isEmpty)
    for property in properties {
      let derived = camelToSnakeCase(property.name)
      #expect(
        property.columnAttribute == (derived == property.column.name ? nil : property.column.name),
        "\(property.column.name) as \(property.name)"
      )
    }
  }

  @Test
  func hostileFixtureReportsEveryRenameAndFallback() {
    let result = run(arguments: GoldenCase.hostile.arguments) { Fixture.data("hostile_metadata") }
    let notes = [
      "schema date is named DateSchema: Date would shadow a type the generated code uses",
      "public.coding_keys is named CodingKeysTable: "
        + "CodingKeys would shadow a type the generated code uses",
      "public.columns is named ColumnsTable: Columns would shadow a type the generated code uses",
      "public.date is named DateTable: Date would shadow a type the generated code uses",
      "public.draft is named DraftTable: Draft would shadow a type the generated code uses",
      "public.type is named TypeTable: Type would shadow a type the generated code uses",
      "enum public.codable is named CodableEnum: "
        + "Codable would shadow a type the generated code uses",
      "public.user_profiles is named UserProfiles2: another type is also named UserProfiles",
      "enum public.user profiles is named UserProfiles3: another type is also named UserProfiles",
      "enum public.mood value self is named selfCase: the enum reserves self",
      "enum public.mood value Self is named selfCase: the enum reserves self",
      "enum public.mood value rawValue is named rawValueCase: the enum reserves rawValue",
      "enum public.mood value init is named initCase: the enum reserves init",
      "enum public.mood value Self is named selfCase2: another value is also named selfCase",
      "enum public.mood value in-progress is named inProgress2: "
        + "another value is also named inProgress",
      "enum public.mood value IN_PROGRESS is named inProgress3: "
        + "another value is also named inProgress",
      "public.hostile.self is named selfColumn: @Table reserves self",
      "public.hostile.columns is named columnsColumn: @Table reserves columns",
      "public.hostile.select_string is named selectStringColumn: @Table reserves selectString",
      "public.hostile.relation_name is named relationNameColumn: @Table reserves relationName",
      "public.hostile.primary_key_columns is named primaryKeyColumnsColumn: "
        + "@Table reserves primaryKeyColumns",
      "public.hostile.userId is named userId2: another column is also named userId",
      "public.hostile.user-id is named userId3: another column is also named userId",
      "public.hostile.span has the type pg_catalog.int4range, which is not mapped; "
        + "it is decoded as JSONValue",
      #"function my"schema.elsewhere(hostile) is not generated: "#
        + "it is not in the schema of public.hostile",
      "function public.anything(hostile) is not generated: it returns record, not a value",
      "function public.books_of(hostile) is not generated: "
        + "it returns inventory.books, which is not generated",
      "function public.duration(hostile) returns the type pg_catalog.interval, "
        + "which is not mapped; it is decoded as JSONValue",
      "function public.id(hostile) is not generated: "
        + "hostile has a column of the same name, which PostgREST resolves",
      "function public.many_ints(hostile) is not generated: "
        + "it returns a set of a scalar type, which PostgREST cannot select as a field",
      "function public.nothing(hostile) is not generated: it returns void, not a value",
      "function public.nowhere(hostile) is not generated: "
        + "it returns unknown, which is not generated",
      "function public.Self is named selfComputed: Columns of public.hostile already has self",
      "function public.UserId is named userIdComputed: "
        + "Columns of public.hostile already has userId",
      "function public.get_things is named getThings2: another member is also named getThings",
    ]
    #expect(result.standardError == notes.map { "supabase-typegen: note: \($0)\n" }.joined())
  }

  /// The integration fixture's computed members, one per rule: a scalar function is a computed
  /// field, a row function a to-one relationship, a `SETOF` row function a to-many one.
  @Test
  func computedMembersFollowTheReturnType() {
    let result = run(arguments: []) { Fixture.integration }
    #expect(result.exitCode == 0)
    #expect(!result.standardError.contains("function"), "\(result.standardError)")
    #expect(
      result.standardOutput.contains(
        """
        extension Channels.Columns {
          var channelMessages: PostgrestToManyRelation<Channels, Messages> {
            .init("channel_messages")
          }
          var firstMessage: PostgrestToOneRelation<Channels, Messages> {
            .init("first_message")
          }
          var shoutedSlug: PostgrestComputedField<Channels, String> {
            .init("shouted_slug")
          }
        }

        """))
    // Only `channels` has any: `get_status(text)` and the rest do not take a row.
    #expect(result.standardOutput.components(separatedBy: ".Columns {").count == 2)
  }

  /// `ROWS 1` marks a set-returning function that returns one row; `todos_matview` is a
  /// materialized view, `users_view` a view and `foreign_table` a foreign table.
  @Test
  func computedMembersBelongToEveryKindOfRelation() {
    let result = run(arguments: []) { Fixture.postgrestTypegen }
    for expected in [
      "extension TodosMatview.Columns {\n  var getTodosByMatview: "
        + "PostgrestToOneRelation<TodosMatview, Todos> {",
      "extension UsersView.Columns {",
      "extension ForeignTable.Columns {",
      "var getUserAuditSetofSingleRow: PostgrestToOneRelation<Users, UsersAudit>",
      "var getTodosFromUser: PostgrestToManyRelation<Users, Todos>",
    ] {
      #expect(result.standardOutput.contains(expected), "\(expected)")
    }
    // One function name on several relations: `blurb_varchar` is on `todos` and `todos_view`.
    #expect(result.standardOutput.components(separatedBy: "var blurbVarchar:").count == 3)
    // Takes two arguments, returns a composite that is no relation, or returns a set of scalars.
    for absent in ["testUnnamedMultipleRows", "testUnnamedRowComposite", "getUserIds", "add"] {
      #expect(!result.standardOutput.contains("var \(absent):"), "\(absent)")
    }
  }

  /// Under `--access-control public` every member of the extension is `public`.
  @Test
  func computedMembersFollowTheAccessControl() {
    let result = run(arguments: ["--access-control", "public"]) { Fixture.integration }
    #expect(result.standardOutput.contains("extension Channels.Columns {\n  public var channel"))
    #expect(!result.standardOutput.contains("\n  var shoutedSlug"))
  }

  /// A computed field alone needs `Foundation` when its type is `Date`.
  @Test
  func computedFieldTypeImportsFoundation() {
    let input = Fixture.integration { object in
      object["tables"] = [["id": 1, "schema": "public", "name": "t"]]
      for key in ["views", "materializedViews", "foreignTables", "primaryKeys", "columns"] {
        object[key] = [Any]()
      }
      object["types"] = [
        ["id": 10, "schema": "public", "name": "t", "enums": [Any](), "type_relation_id": 1],
        [
          "id": 1184, "schema": "pg_catalog", "name": "timestamptz", "enums": [Any](),
          "type_relation_id": NSNull(),
        ],
      ]
      object["functions"] = [
        [
          "schema": "public", "name": "seen_at", "args": [["mode": "in", "type_id": 10]],
          "identity_argument_types": "t", "return_type_id": 1184,
          "return_type_relation_id": NSNull(), "is_set_returning_function": false,
          "prorows": NSNull(),
        ]
      ]
    }
    let result = run(arguments: []) { input }
    #expect(result.exitCode == 0, "\(result.standardError)")
    #expect(result.standardOutput.contains("import Foundation"))
    #expect(result.standardOutput.contains("PostgrestComputedField<T, Date>"))
  }

  /// An enum of a schema that is not selected is generated when only a computed field returns it.
  @Test
  func computedFieldEnumOfAnotherSchemaIsGenerated() {
    let input = Fixture.integration { object in
      object["schemas"] = [["name": "public"]]
      object["tables"] = [["id": 1, "schema": "public", "name": "t"]]
      for key in ["views", "materializedViews", "foreignTables", "primaryKeys", "columns"] {
        object[key] = [Any]()
      }
      object["types"] = [
        ["id": 10, "schema": "public", "name": "t", "enums": [Any](), "type_relation_id": 1],
        [
          "id": 20, "schema": "other", "name": "mood", "enums": ["happy", "sad"],
          "type_relation_id": NSNull(),
        ],
      ]
      object["functions"] = [
        [
          "schema": "public", "name": "mood", "args": [["mode": "in", "type_id": 10]],
          "identity_argument_types": "t", "return_type_id": 20,
          "return_type_relation_id": NSNull(), "is_set_returning_function": false,
          "prorows": NSNull(),
        ]
      ]
    }
    let result = run(arguments: []) { input }
    #expect(result.exitCode == 0)
    #expect(result.standardError.isEmpty, "\(result.standardError)")
    #expect(result.standardOutput.contains("enum OtherMood: String,"))
    #expect(result.standardOutput.contains("PostgrestComputedField<T, OtherMood>"))
  }

  /// A relation listed twice, here in both `tables` and `views`, is generated once, as the first.
  @Test
  func relationListedTwiceIsGeneratedOnce() {
    let input = Fixture.integration { object in
      object["tables"] = [["id": 1, "schema": "public", "name": "t"]]
      object["views"] = [
        [
          "id": 2, "schema": "public", "name": "t", "is_updatable": false,
          "is_insert_enabled": false, "is_update_enabled": false,
        ]
      ]
      for key in ["materializedViews", "foreignTables", "primaryKeys", "columns", "functions"] {
        object[key] = [Any]()
      }
    }
    let result = run(arguments: []) { input }
    #expect(result.exitCode == 0, "\(result.standardError)")
    #expect(result.standardOutput.contains("@Table(\"t\")\nstruct T {"))
    #expect(result.standardOutput.components(separatedBy: "@Table(").count == 2)
  }

  /// A document with one table, `public.t`, whose only column `c` has the given type, and the
  /// enum `public.status`.
  private func generated(format: String, typeSchema: String) -> RunResult {
    let input = Fixture.integration { object in
      object["tables"] = [["id": 1, "schema": "public", "name": "t"]]
      for key in ["views", "materializedViews", "foreignTables", "primaryKeys", "functions"] {
        object[key] = [Any]()
      }
      object["columns"] = [
        [
          "table_id": 1, "ordinal_position": 1, "name": "c", "format": format,
          "type_schema": typeSchema, "default_value": NSNull(), "identity_generation": NSNull(),
          "is_generated": false, "is_nullable": false,
        ]
      ]
      object["types"] = [
        [
          "id": 1, "schema": "public", "name": "status",
          "enums": ["pending", "in_progress", "done"], "type_relation_id": NSNull(),
        ]
      ]
    }
    return run(arguments: []) { input }
  }

  @Test(
    arguments: [
      ("uuid", "pg_catalog", "UUID"),
      ("text", "pg_catalog", "String"),
      ("varchar", "pg_catalog", "String"),
      ("bpchar", "pg_catalog", "String"),
      ("char", "pg_catalog", "String"),
      ("citext", "extensions", "String"),
      ("bool", "pg_catalog", "Bool"),
      ("int2", "pg_catalog", "Int"),
      ("int4", "pg_catalog", "Int"),
      ("int8", "pg_catalog", "Int"),
      ("float4", "pg_catalog", "Double"),
      ("float8", "pg_catalog", "Double"),
      ("numeric", "pg_catalog", "Decimal"),
      ("timestamptz", "pg_catalog", "Date"),
      ("timestamp", "pg_catalog", "Date"),
      ("date", "pg_catalog", "Date"),
      ("json", "pg_catalog", "JSONValue"),
      ("jsonb", "pg_catalog", "JSONValue"),
      ("_int4", "pg_catalog", "[Int]"),
      ("_text", "pg_catalog", "[String]"),
      ("status", "public", "Status"),
      ("_status", "public", "[Status]"),
    ]
  )
  func postgresTypeMapsToSwiftType(format: String, typeSchema: String, swiftType: String) {
    let result = generated(format: format, typeSchema: typeSchema)
    #expect(result.exitCode == 0)
    #expect(result.standardError.isEmpty)
    #expect(result.standardOutput.contains("\n  var c: \(swiftType)\n"))
  }

  @Test(
    arguments: [
      ("bytea", "pg_catalog"), ("interval", "pg_catalog"), ("time", "pg_catalog"),
      ("int4range", "pg_catalog"), ("address", "public"), ("geometry", "extensions"),
      ("_bytea", "pg_catalog"),
    ]
  )
  func unmappedTypeIsJSONValueWithANote(format: String, typeSchema: String) {
    let result = generated(format: format, typeSchema: typeSchema)
    let element = arrayElement(of: format) ?? format
    #expect(result.exitCode == 0)
    #expect(
      result.standardError
        == "supabase-typegen: note: public.t.c has the type \(typeSchema).\(element), which is "
        + "not mapped; it is decoded as JSONValue\n"
    )
    #expect(
      result.standardOutput.contains(
        arrayElement(of: format) == nil ? "\n  var c: JSONValue\n" : "\n  var c: [JSONValue]\n"))
  }

  @Test
  func enumBecomesASwiftEnum() {
    let result = generated(format: "status", typeSchema: "public")
    #expect(
      result.standardOutput.contains(
        """
        enum Status: String, Codable, Hashable, Sendable, PostgrestFilterValue {
          case pending
          case inProgress = "in_progress"
          case done
        }
        """
      )
    )
  }

  @Test
  func typeNameClashAcrossSchemasIsADataError() {
    let result = run(arguments: []) { Fixture.data("hostile_metadata") }
    #expect(
      result
        == RunResult(
          exitCode: 65,
          standardError: "supabase-typegen: inventory.books and public.inventory_books both "
            + "become the Swift type InventoryBooks\n"
        )
    )
  }

  @Test
  func schemaEnumClashingWithARelationIsADataError() {
    let input = Fixture.integration { object in
      object["schemas"] = [["name": "public"], ["name": "todos"]]
    }
    let result = run(arguments: []) { input }
    #expect(result.exitCode == 65)
    #expect(
      result.standardError
        == "supabase-typegen: public.todos and schema todos both become the Swift type Todos\n")
  }

  private func column(
    hasDefault: Bool = false,
    identity: IdentityGeneration? = nil,
    isGenerated: Bool = false
  ) -> DatabaseModel.Column {
    DatabaseModel.Column(
      name: "c", format: "int4", typeSchema: "pg_catalog", enumID: nil, hasDefault: hasDefault,
      identityGeneration: identity, isGenerated: isGenerated, isNullable: false)
  }

  @Test
  func markersFollowTheColumnMetadata() {
    func markers(_ column: DatabaseModel.Column, key: Bool = false) -> [String] {
      FilePlan.markers(of: column, isPrimaryKey: key)
    }
    #expect(markers(column()).isEmpty)
    #expect(markers(column(), key: true) == ["PrimaryKey"])
    #expect(markers(column(hasDefault: true)) == ["Default"])
    #expect(markers(column(identity: .byDefault)) == ["Default"])
    #expect(markers(column(identity: .always)) == ["Generated"])
    #expect(markers(column(isGenerated: true)) == ["Generated"])
    // A generated column's expression is its `default_value`; `@Generated` alone is enough.
    #expect(markers(column(hasDefault: true, isGenerated: true)) == ["Generated"])
    #expect(
      markers(column(hasDefault: true, identity: .always), key: true) == [
        "PrimaryKey", "Generated",
      ]
    )
    #expect(markers(column(hasDefault: true), key: true) == ["PrimaryKey", "Default"])
  }

  /// The integration fixture's `updatable_view` with the given flags; `nil` removes the key.
  private func tableAttribute(
    isUpdatable: Bool, isInsertEnabled: Bool?, isUpdateEnabled: Bool?
  ) -> String? {
    let input = Fixture.integration { object in
      var view = (object["views"] as! [[String: Any]])
        .first { $0["name"] as? String == "updatable_view" }!
      view["is_updatable"] = isUpdatable
      view["is_insert_enabled"] = isInsertEnabled
      view["is_update_enabled"] = isUpdateEnabled
      object["views"] = [view]
    }
    return run(arguments: []) { input }.standardOutput
      .split(separator: "\n").first { $0.hasPrefix("@Table(\"updatable_view\"") }.map(String.init)
  }

  @Test(
    arguments: [
      (true, nil, nil, false), (false, nil, nil, true),
      (false, true, nil, false), (false, nil, true, false),
      (true, false, false, true), (false, true, true, false),
    ] as [(Bool, Bool?, Bool?, Bool)]
  )
  func viewIsReadOnlyUnlessItAcceptsWrites(
    isUpdatable: Bool, insert: Bool?, update: Bool?, readOnly: Bool
  ) {
    #expect(
      tableAttribute(isUpdatable: isUpdatable, isInsertEnabled: insert, isUpdateEnabled: update)
        == (readOnly ? #"@Table("updatable_view", readOnly: true)"# : #"@Table("updatable_view")"#)
    )
  }

  @Test
  func nullablePrimaryKeyIsADataErrorNamingTheColumn() {
    let input = Fixture.integration { object in
      var columns = object["columns"] as! [[String: Any]]
      for index in columns.indices
      where columns[index]["table"] as? String == "channels"
        && columns[index]["name"] as? String == "id"
      {
        columns[index]["is_nullable"] = true
      }
      object["columns"] = columns
    }
    let result = run(arguments: []) { input }
    #expect(
      result
        == RunResult(
          exitCode: 65,
          standardError: "supabase-typegen: public.channels.id is a primary key column but is "
            + "nullable; @PrimaryKey cannot mark an Optional property\n"
        )
    )
  }
}
