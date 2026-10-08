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
  var golden: String

  var schemas: [String] {
    zip(arguments, arguments.dropFirst()).filter { $0.0 == "--schema" }.map(\.1)
  }

  var testDescription: String { golden }

  static let all = [
    GoldenCase(fixture: "generator_metadata", arguments: [], golden: "generator_metadata"),
    GoldenCase(
      fixture: "postgrest_typegen_metadata",
      arguments: ["--access-control", "public"],
      golden: "postgrest_typegen_metadata_public"
    ),
    // Without `inventory`, whose `books` clashes with `public.inventory_books`.
    GoldenCase(
      fixture: "hostile_metadata",
      arguments: ["--schema", "public", "--schema", #"my"schema"#],
      golden: "hostile_metadata"
    ),
  ]
}

@Suite
struct EmitterTests {
  private static let goldens = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("__Goldens__")

  @Test(arguments: GoldenCase.all)
  func outputMatchesTheGoldenFile(_ golden: GoldenCase) throws {
    let result = run(arguments: golden.arguments) { Fixture.data(golden.fixture) }
    #expect(result.exitCode == 0, "\(result.standardError)")

    let url = Self.goldens.appendingPathComponent("\(golden.golden).swift.golden")
    if ProcessInfo.processInfo.environment["SUPABASE_TYPEGEN_RECORD"] == "1" {
      try Data(result.standardOutput.utf8).write(to: url)
      Issue.record("Recorded \(url.lastPathComponent); run again without SUPABASE_TYPEGEN_RECORD")
      return
    }
    let expected = try String(contentsOf: url, encoding: .utf8)
    #expect(
      result.standardOutput == expected,
      "Output differs from \(url.lastPathComponent); record with SUPABASE_TYPEGEN_RECORD=1"
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
    let result = run(arguments: GoldenCase.all[2].arguments) { Fixture.data("hostile_metadata") }
    let notes = [
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
      "enum public.mood value self is named selfCase: the struct reserves self",
      "enum public.mood value Self is named selfCase: the struct reserves self",
      "enum public.mood value rawValue is named rawValueCase: the struct reserves rawValue",
      "enum public.mood value init is named initCase: the struct reserves init",
      "enum public.mood value Self is named selfCase2: another value is also named selfCase",
      "enum public.mood value in-progress is named inProgress2: "
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
    ]
    #expect(result.standardError == notes.map { "supabase-typegen: note: \($0)\n" }.joined())
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
          "id": 1, "schema": "public", "name": "status", "enums": ["pending", "done"],
          "type_relation_id": NSNull(),
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
    let element = format.hasPrefix("_") ? String(format.dropFirst()) : format
    #expect(result.exitCode == 0)
    #expect(
      result.standardError
        == "supabase-typegen: note: public.t.c has the type \(typeSchema).\(element), which is "
        + "not mapped; it is decoded as JSONValue\n"
    )
    #expect(
      result.standardOutput.contains(
        format.hasPrefix("_") ? "\n  var c: [JSONValue]\n" : "\n  var c: JSONValue\n"))
  }

  @Test
  func enumBecomesARawRepresentableStruct() {
    let result = generated(format: "status", typeSchema: "public")
    #expect(
      result.standardOutput.contains(
        """
        struct Status: RawRepresentable, Codable, Hashable, Sendable,
          ExpressibleByStringLiteral, PostgrestFilterValue
        {
          let rawValue: String
          init(rawValue: String) {
            self.rawValue = rawValue
          }
          init(stringLiteral value: String) {
            self.init(rawValue: value)
          }

          static let pending: Status = "pending"
          static let done: Status = "done"
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
      var views = object["views"] as! [[String: Any]]
      views[0]["is_updatable"] = isUpdatable
      views[0]["is_insert_enabled"] = isInsertEnabled
      views[0]["is_update_enabled"] = isUpdateEnabled
      object["views"] = views
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
