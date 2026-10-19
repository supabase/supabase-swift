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
        TableMacro.Arguments(name: "todos", schema: nil, readOnly: readOnly),
        hasPrimaryKey: hasPrimaryKey
      ),
      missing: missing.map { TypeSyntax(stringLiteral: $0) }
    )
  }

  @Test
  func namesEveryLinkInTheRefinementChain() {
    // `_PostgrestWritableRelation` alone is not enough: a macro-generated extension does not derive
    // the inherited conformance, and reports a missing `_PostgrestRelation` with no useful note.
    #expect(
      clause(
        readOnly: false,
        missing: ["Decodable", "Sendable", "_PostgrestRelation", "_PostgrestWritableRelation"]
      ) == ": Decodable, Sendable, _PostgrestRelation, _PostgrestWritableRelation"
    )
  }

  @Test
  func aDeclaredKeyAddsTheKeyedRelation() {
    #expect(
      clause(
        readOnly: false,
        hasPrimaryKey: true,
        missing: [
          "Decodable", "Sendable", "_PostgrestRelation", "_PostgrestKeyedRelation",
          "_PostgrestWritableRelation",
        ]
      )
        == ": Decodable, Sendable, _PostgrestRelation, _PostgrestKeyedRelation, _PostgrestWritableRelation"
    )
  }

  @Test
  func aKeyedViewIsKeyedButNotWritable() {
    #expect(
      clause(
        readOnly: true,
        hasPrimaryKey: true,
        missing: ["Decodable", "Sendable", "_PostgrestRelation", "_PostgrestKeyedRelation"]
      ) == ": Decodable, Sendable, _PostgrestRelation, _PostgrestKeyedRelation"
    )
  }

  @Test
  func readOnlyStopsAtTheReadableRelation() {
    #expect(
      clause(readOnly: true, missing: ["Decodable", "Sendable", "_PostgrestRelation"])
        == ": Decodable, Sendable, _PostgrestRelation"
    )
  }

  @Test
  func skipsWhatTheTypeAlreadyDeclares() {
    #expect(
      clause(readOnly: false, missing: ["_PostgrestRelation", "_PostgrestWritableRelation"])
        == ": _PostgrestRelation, _PostgrestWritableRelation"
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
        isGenerated: false,
        explicitColumn: nil
      ).unwrappedType
    }
    #expect(unwrapped("Date?") == "Date")
    #expect(unwrapped("Optional<Date>") == "Date")
    #expect(unwrapped("[String]?") == "[String]")
    #expect(unwrapped("Optional<[Int]>") == "[Int]")
    #expect(unwrapped("String") == "String")
    #expect(unwrapped("String!") == "String")
    #expect(unwrapped("Optional<Int>!") == "Int")
    #expect(unwrapped("Int??") == "Int")
  }

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
