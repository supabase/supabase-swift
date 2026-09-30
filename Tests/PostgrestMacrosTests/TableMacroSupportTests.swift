//
//  TableMacroSupportTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import SwiftSyntax
import SwiftSyntaxBuilder
import Testing

@testable import PostgrestMacrosPlugin

/// Covers the two pieces `assertMacro` cannot reach.
///
/// `MacroTesting` expands a macro without its declaration, so it always passes an empty
/// `conformingTo:` and the recorded expansions show `extension Todo {` with no inheritance clause.
/// The clause is what makes the conformance land, so it is asserted here directly.
@Suite
struct TableMacroSupportTests {
  private func clause(
    readOnly: Bool,
    hasPrimaryKey: Bool = false,
    missing: [String]
  ) -> String {
    inheritanceClause(
      wanted: TableMacro.wantedConformances(
        TableMacro.Arguments(name: "todos", schema: "public", readOnly: readOnly),
        hasPrimaryKey: hasPrimaryKey
      ),
      missing: missing.map { TypeSyntax(stringLiteral: $0) }
    )
  }

  @Test
  func namesEveryLinkInTheRefinementChain() {
    // `PostgrestWritableRelation` alone is not enough: a macro-generated extension does not derive
    // the inherited conformance, and reports a missing `PostgrestRelation` with no useful note.
    #expect(
      clause(
        readOnly: false,
        missing: ["Decodable", "Sendable", "PostgrestRelation", "PostgrestWritableRelation"]
      ) == ": Decodable, Sendable, PostgrestRelation, PostgrestWritableRelation"
    )
  }

  @Test
  func aDeclaredKeyAddsTheKeyedRelation() {
    // What gates the derived-target `upsert`. Listed after `PostgrestRelation` for the same reason
    // the whole chain is listed: the generated extension does not derive an inherited conformance.
    #expect(
      clause(
        readOnly: false,
        hasPrimaryKey: true,
        missing: [
          "Decodable", "Sendable", "PostgrestRelation", "PostgrestKeyedRelation",
          "PostgrestWritableRelation",
        ]
      )
        == ": Decodable, Sendable, PostgrestRelation, PostgrestKeyedRelation, PostgrestWritableRelation"
    )
  }

  @Test
  func aKeyedViewIsKeyedButNotWritable() {
    // A view Postgres reports a key for is still read-only. The two axes are independent.
    #expect(
      clause(
        readOnly: true,
        hasPrimaryKey: true,
        missing: ["Decodable", "Sendable", "PostgrestRelation", "PostgrestKeyedRelation"]
      ) == ": Decodable, Sendable, PostgrestRelation, PostgrestKeyedRelation"
    )
  }

  @Test
  func readOnlyStopsAtTheReadableRelation() {
    #expect(
      clause(readOnly: true, missing: ["Decodable", "Sendable", "PostgrestRelation"])
        == ": Decodable, Sendable, PostgrestRelation"
    )
  }

  @Test
  func skipsWhatTheTypeAlreadyDeclares() {
    // `struct Todo: Decodable, Sendable` must not get a second Decodable conformance.
    #expect(
      clause(readOnly: false, missing: ["PostgrestRelation", "PostgrestWritableRelation"])
        == ": PostgrestRelation, PostgrestWritableRelation"
    )
    #expect(clause(readOnly: false, missing: []) == "")
  }

  @Test
  func convertsPropertyNamesToColumnNames() {
    #expect(camelToSnakeCase("isDone") == "is_done")
    #expect(camelToSnakeCase("dueDate") == "due_date")
    #expect(camelToSnakeCase("task") == "task")
    #expect(camelToSnakeCase("htmlURL") == "html_url")
    #expect(camelToSnakeCase("urlSession") == "url_session")
    #expect(camelToSnakeCase("id") == "id")
  }

  @Test
  func unwrapsEveryOptionalSpelling() {
    func unwrapped(_ type: String) -> String {
      StoredProperty(
        name: "x", type: type, isOptional: true, isPrimaryKey: false, hasDefault: false,
        explicitColumn: nil
      ).unwrappedType
    }
    #expect(unwrapped("Date?") == "Date")
    #expect(unwrapped("Optional<Date>") == "Date")
    #expect(unwrapped("[String]?") == "[String]")
    #expect(unwrapped("Optional<[Int]>") == "[Int]")
    #expect(unwrapped("String") == "String")
    // An implicitly unwrapped optional is a nullable column too, and `String!` in a generic
    // argument does not compile at all.
    #expect(unwrapped("String!") == "String")
    // Every layer comes off. One left on gives a column whose `Value` is optional, which loses
    // every operator, because `Optional` does not conform to `PostgrestFilterValue`.
    #expect(unwrapped("Optional<Int>!") == "Int")
    #expect(unwrapped("Int??") == "Int")
  }

  /// The two used to test separate sets of spellings, and disagreed on `Optional<Int>!`.
  @Test
  func optionalityAgreesWithUnwrapping() {
    for type in ["Date?", "Optional<Date>", "String!", "Optional<Int>!", "Int??"] {
      #expect(postgrestIsOptionalType(type), "\(type) should be optional")
      #expect(postgrestUnwrapOptionalType(type) != nil)
    }
    for type in ["String", "[Int]", "Dictionary<String, Int>"] {
      #expect(!postgrestIsOptionalType(type), "\(type) should not be optional")
      #expect(postgrestUnwrapOptionalType(type) == nil)
    }
  }
}
