//
//  Generation.swift
//  PostgrestMacrosPlugin
//
//  Created by Guilherme Souza on 21/08/26.
//

import SwiftSyntax

/// The `CodingKeys` enum for a property list, or `nil` when there is nothing to map.
///
/// `@Table` and `@SelectionOf` share it so a relation and a selection of it spell the same column
/// the same way.
func codingKeys(for properties: [StoredProperty], indent: String = "  ") -> String? {
  guard !properties.isEmpty else { return nil }
  var lines = ["\(indent)enum CodingKeys: String, CodingKey {"]
  for property in properties {
    lines.append("\(indent)  case \(property.name) = \"\(property.columnName)\"")
  }
  lines.append("\(indent)}")
  return lines.joined(separator: "\n")
}

/// The inheritance clause to emit on a macro-generated extension, or `""` when there is nothing
/// left to add.
///
/// Two rules are baked in, and both fail confusingly if you skip them:
///
/// - `wanted` must name every protocol in the refinement chain. A macro-generated extension does
///   not derive an inherited conformance, so `extension Todo: PostgrestWritableRelation` alone
///   reports a missing `PostgrestRelation` with no note saying which requirement is unmet.
/// - `missing` is the compiler's `conformingTo:` list, which excludes whatever the type already
///   declares. Filtering by it is what keeps `struct Todo: Decodable` from getting a second
///   `Decodable` conformance.
func inheritanceClause(wanted: [String], missing: [TypeSyntax]) -> String {
  let missing = Set(missing.map(\.trimmedDescription))
  let needed = wanted.filter(missing.contains)
  return needed.isEmpty ? "" : ": \(needed.joined(separator: ", "))"
}
