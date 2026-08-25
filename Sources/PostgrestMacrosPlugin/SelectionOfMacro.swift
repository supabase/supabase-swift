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
    if declaration.postgrestDiagnoseMultipleBindings(macro: "@SelectionOf", in: context) {
      return []
    }
    if declaration.postgrestDiagnoseUnannotatedProperties(macro: "@SelectionOf", in: context) {
      return []
    }
    let access = declaration.postgrestAccessLevel
    let properties = declaration.postgrestStoredProperties()

    var body: [String] = [
      "  \(access)typealias Source = \(relation)",
      "  \(access)static let selectString = \"\(properties.map(\.columnName).joined(separator: ","))\"",
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

  /// The cross-type check.
  ///
  /// A macro sees syntax only and cannot inspect the relation's members. It can *emit* references
  /// to them, though, and the compiler checks the expansion — so a property that names no column
  /// on the relation fails on the emitted line. That is what makes a declared selection fully
  /// checked rather than checked by convention.
  static func columnCheck(relation: String, properties: [StoredProperty]) -> String {
    var lines = [
      "  /// Fails to compile if a property does not name a column on \(relation).",
      "  private static let _columnCheck: [String] = [",
    ]
    for property in properties {
      lines.append("    \(relation).columnName(for: \\\(relation).\(property.name)),")
    }
    lines.append("  ]")
    return lines.joined(separator: "\n")
  }
}
