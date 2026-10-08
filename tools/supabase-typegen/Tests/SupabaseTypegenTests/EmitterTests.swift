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
      "public.date is named DateTable: Date would shadow a type the generated code uses",
      "public.type is named TypeTable: Type would shadow a type the generated code uses",
      "public.hostile.self is named selfColumn: @Table reserves self",
      "public.hostile.columns is named columnsColumn: @Table reserves columns",
      "public.hostile.select_string is named selectStringColumn: @Table reserves selectString",
      "public.hostile.relation_name is named relationNameColumn: @Table reserves relationName",
      "public.hostile.primary_key_columns is named primaryKeyColumnsColumn: "
        + "@Table reserves primaryKeyColumns",
      "public.hostile.userId is named userId2: another column is also named userId",
      "public.hostile.user-id is named userId3: another column is also named userId",
      "public.hostile.mood has the enum type public.mood, which is not generated yet; "
        + "it is decoded as JSONValue",
      "public.hostile.moods has the enum type public.mood, which is not generated yet; "
        + "it is decoded as JSONValue",
      "public.hostile.span has the type pg_catalog.int4range, which is not mapped; "
        + "it is decoded as JSONValue",
      "public.user_profiles is named UserProfiles2: another relation is also named UserProfiles",
    ]
    #expect(result.standardError == notes.map { "supabase-typegen: note: \($0)\n" }.joined())
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
}
