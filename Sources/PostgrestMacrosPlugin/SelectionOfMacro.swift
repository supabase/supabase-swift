//
//  SelectionOfMacro.swift
//  PostgrestMacrosPlugin
//
//  Created by Guilherme Souza on 21/08/26.
//

import SwiftSyntax
import SwiftSyntaxMacros

/// Expands `@SelectionOf` into a selection conformance.
///
/// Like ``TableMacro``, everything is emitted from the extension role and the inheritance clause
/// names the whole refinement chain — a macro-generated extension derives neither.
public struct SelectionOfMacro: ExtensionMacro {
  /// The relation named by `@SelectionOf(Todo.self)`, or `nil` if the argument is not a `T.self`.
  static func relation(from node: AttributeSyntax) -> String? {
    guard
      let expression = node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression,
      let base = expression.as(MemberAccessExprSyntax.self)?.base
    else { return nil }
    return base.trimmedDescription
  }

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard declaration.is(StructDeclSyntax.self) else {
      context.error("@SelectionOf can only be applied to a struct", at: node)
      return []
    }
    guard let relation = relation(from: node) else {
      context.error(
        "@SelectionOf requires a relation type, e.g. @SelectionOf(Todo.self)",
        at: node
      )
      return []
    }
    if declaration.postgrestDiagnoseUnannotatedProperties(macro: "@SelectionOf", in: context) {
      return []
    }
    let access = declaration.postgrestAccessLevel
    let properties = declaration.postgrestStoredProperties()

    var body: [String] = [
      "  \(access)typealias Source = \(relation)",
      selectString(access: access, relation: relation, properties: properties),
    ]
    if let codingKeys = codingKeys(for: properties) {
      body.append(codingKeys)
    }
    body.append(columnCheck(relation: relation, properties: properties))

    let clause = inheritanceClause(
      wanted: ["Decodable", "Sendable", "PostgrestSelection"], missing: protocols
    )
    return [
      try ExtensionDeclSyntax(
        """
        extension \(type.trimmed)\(raw: clause) {
        \(raw: body.joined(separator: "\n\n"))
        }
        """
      )
    ]
  }

  /// The `select` list, with each column read from the relation rather than re-derived here.
  ///
  /// A selection knows its own property names; it does not know what column the relation maps them
  /// to. Snake-casing locally gets that wrong the moment the relation carries a `@Column`:
  /// a selection declaring `var dueDate: Date?` over a relation with `@Column("due_at")` asked
  /// PostgREST for `due_date`, a column that does not exist. Nothing caught it — `_columnCheck`
  /// proves the *key path* resolves, not that the name matches.
  ///
  /// So the column comes from `Source.columns`, the namespace the relation already validated.
  /// That makes the value a runtime one rather than a literal, which is why it is assembled
  /// with `joined(separator:)`.
  ///
  /// Each entry is emitted as a PostgREST alias, `key:column`. The alias is what keeps
  /// `CodingKeys` correct: the response comes back keyed by the selection's own name, so the
  /// generated coding keys need no knowledge of the relation's column names — which a macro could
  /// not give them anyway, since a `CodingKey` raw value has to be a literal. When the two names
  /// agree the alias is a no-op, so it is emitted unconditionally rather than guessed at.
  static func selectString(
    access: String, relation: String, properties: [StoredProperty]
  ) -> String {
    guard !properties.isEmpty else {
      return "  \(access)static let selectString = \"\""
    }

    var lines = ["  \(access)static let selectString = ["]
    for property in properties {
      lines.append(
        "    \"\(property.columnName):\\(\(relation).columns.\(property.name).postgrestExpression)\","
      )
    }
    lines.append("  ].joined(separator: \",\")")
    return lines.joined(separator: "\n")
  }

  /// The cross-type check.
  ///
  /// A macro sees syntax only and cannot inspect the relation's members. It can *emit* references
  /// to them, though, and the compiler checks the expansion — so a property that names no column
  /// on the relation fails on the emitted line. That is what makes a declared selection fully
  /// checked rather than checked by convention.
  ///
  /// Now that ``selectString(access:relation:properties:)`` reads `.postgrestExpression` off
  /// every property's column, it carries the same proof, and this array is redundant. It is kept
  /// because it says out loud what the check is for; the diagnostic a reader gets from a bad
  /// property name is the same either way.
  static func columnCheck(relation: String, properties: [StoredProperty]) -> String {
    var lines = [
      "  /// Fails to compile if a property does not name a column on \(relation).",
      "  private static let _columnCheck: [String] = [",
    ]
    for property in properties {
      lines.append("    \(relation).columns.\(property.name).postgrestExpression,")
    }
    lines.append("  ]")
    return lines.joined(separator: "\n")
  }
}
