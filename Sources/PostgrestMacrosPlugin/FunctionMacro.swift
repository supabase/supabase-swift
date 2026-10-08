//
//  FunctionMacro.swift
//  PostgrestMacrosPlugin
//
//  Created by Guilherme Souza on 07/10/26.
//

import SwiftSyntax
import SwiftSyntaxMacros

public struct FunctionMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard declaration.is(StructDeclSyntax.self) else {
      context.error("@Function can only be applied to a struct", at: node)
      return []
    }
    if let relationship = declaration.postgrestRelationshipAttribute() {
      context.error(
        "@Relationship belongs on a @SelectionOf type, not on @Function", at: relationship)
      return []
    }
    if declaration.postgrestDiagnoseUnannotatedProperties(macro: "@Function", in: context) {
      return []
    }
    // Reuses `@Table`'s argument reader: `@Function` takes the same `name` and `schema:` pair.
    let arguments = TableMacro.arguments(from: node)
    var schema = "PostgREST.PublicSchema"
    if let expression = arguments.schema {
      guard let written = TableMacro.schemaType(of: expression) else {
        context.error("schema: needs a schema type, as in `PrivateSchema.self`", at: expression)
        return []
      }
      schema = written
    }
    let access = declaration.postgrestAccessLevel
    let properties = declaration.postgrestStoredProperties()

    var body: [String] = [
      "  \(access)static let functionName = \"\(arguments.name)\"",
      "  \(access)typealias Schema = \(schema)",
    ]
    // The arguments encode under their database names: `@Column` first, snake_case otherwise,
    // from the same input `@Table` reads, so an argument is never sent under its Swift spelling.
    if let codingKeys = codingKeys(for: properties) {
      body.append(codingKeys)
    }

    let clause = inheritanceClause(
      wanted: ["Encodable", "Sendable", "PostgrestFunction"], missing: protocols)
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
}
