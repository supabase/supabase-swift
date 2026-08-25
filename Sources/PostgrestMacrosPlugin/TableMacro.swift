//
//  TableMacro.swift
//  PostgrestMacrosPlugin
//
//  Created by Guilherme Souza on 21/08/26.
//

import SwiftSyntax
import SwiftSyntaxMacros

/// Expands `@Table` into a relation conformance.
///
/// Everything is emitted from the extension role, and none of it from a member role. Two rules
/// force that shape, and both fail confusingly if you get them wrong:
///
/// - A macro-generated extension cannot witness a requirement with a member added by a *member*
///   role of the same attribute. Splitting the witnesses across the two roles compiles as
///   hand-written source and fails as an expansion.
/// - The emitted inheritance clause must name every protocol in the refinement chain.
///   `extension Todo: PostgrestWritableRelation` alone reports "does not conform to inherited
///   protocol PostgrestRelation", with no note saying which requirement is missing.
public struct TableMacro: ExtensionMacro {
  // MARK: Arguments

  struct Arguments {
    var name: String
    var schema: String
    var readOnly: Bool
  }

  static func arguments(from node: AttributeSyntax) -> Arguments {
    var name = ""
    var schema = "public"
    var readOnly = false
    for argument in node.arguments?.as(LabeledExprListSyntax.self) ?? [] {
      switch argument.label?.text {
      case nil:
        name = argument.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue ?? ""
      case "schema":
        schema =
          argument.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue ?? "public"
      case "readOnly":
        readOnly = argument.expression.as(BooleanLiteralExprSyntax.self)?.literal.text == "true"
      default:
        break
      }
    }
    return Arguments(name: name, schema: schema, readOnly: readOnly)
  }

  // MARK: Expansion

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard declaration.is(StructDeclSyntax.self) else {
      throw MacroExpansionErrorMessage("@Table can only be applied to a struct")
    }
    let arguments = arguments(from: node)
    let access = declaration.postgrestAccessLevel
    let properties = declaration.postgrestStoredProperties()

    var body: [String] = [
      "  \(access)static let relationName = \"\(arguments.name)\"",
      "  \(access)static let schema = \"\(arguments.schema)\"",
      "  \(access)static let selectString = \"*\"",
      columnNameFunction(access: access, type: type.trimmedDescription, properties: properties),
    ]
    if let codingKeys = codingKeys(for: properties) {
      body.append(codingKeys)
    }
    if !arguments.readOnly {
      // `Insert` drops the primary key and makes defaulted columns optional, so a row can be
      // inserted without naming a column the database fills in. `Update` makes every column
      // optional, so a partial update names only what it changes.
      let writable = properties.filter { !$0.isPrimaryKey }
      body.append(
        writeShape(
          named: "Insert",
          access: access,
          fields: writable.map { ($0, $0.isOptional || $0.hasDefault ? $0.optionalType : $0.type) }
        )
      )
      body.append(
        writeShape(named: "Update", access: access, fields: writable.map { ($0, $0.optionalType) })
      )
    }

    return [
      try ExtensionDeclSyntax(
        """
        extension \(type.trimmed)\(raw: inheritanceClause(arguments, protocols)) {
        \(raw: body.joined(separator: "\n\n"))
        }
        """
      )
    ]
  }

  // MARK: Generation

  /// The inheritance clause to emit, or `""` when the type already declares everything.
  ///
  /// `protocols` is the subset of the attribute's declared `conformances:` the type does not
  /// already satisfy, so a user who writes `struct Todo: Decodable` gets no duplicate — and no
  /// "redundant conformance" error.
  ///
  /// `Decodable` is in the list and `Encodable` is not: rows are decoded from responses, and writes
  /// go out through the `Encodable` `Insert` and `Update` shapes.
  static func inheritanceClause(_ arguments: Arguments, _ protocols: [TypeSyntax]) -> String {
    let wanted = [
      "Decodable",
      "Sendable",
      "PostgrestRelation",
      arguments.readOnly ? nil : "PostgrestWritableRelation",
    ].compactMap { $0 }
    let missing = Set(protocols.map(\.trimmedDescription))
    let needed = wanted.filter(missing.contains)
    return needed.isEmpty ? "" : ": \(needed.joined(separator: ", "))"
  }

  /// The key-path-to-column mapping.
  ///
  /// Every stored property gets a case, so `default` is reachable only through a key path to a
  /// computed property — a mistake at the call site, not a query worth sending. `fatalError` says
  /// so immediately; returning `""` would build a query with an empty column name and leave
  /// PostgREST to reject it with a 400 that never names the key path.
  static func columnNameFunction(
    access: String,
    type: String,
    properties: [StoredProperty]
  ) -> String {
    var lines = [
      "  \(access)static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {",
      "    switch keyPath {",
    ]
    for property in properties {
      lines.append("    case \\Self.\(property.name):")
      lines.append("      return \"\(property.columnName)\"")
    }
    lines.append("    default:")
    lines.append("      fatalError(\"\(type): no column is mapped for that key path\")")
    lines.append("    }")
    lines.append("  }")
    return lines.joined(separator: "\n")
  }

  /// The `CodingKeys` enum, or `nil` when there is nothing to map.
  ///
  /// The same property list drives this and the column mapping, so the write path and the filter
  /// path cannot disagree about a column name.
  static func codingKeys(for properties: [StoredProperty], indent: String = "  ") -> String? {
    guard !properties.isEmpty else { return nil }
    var lines = ["\(indent)enum CodingKeys: String, CodingKey {"]
    for property in properties {
      lines.append("\(indent)  case \(property.name) = \"\(property.columnName)\"")
    }
    lines.append("\(indent)}")
    return lines.joined(separator: "\n")
  }

  /// One of the nested write shapes, with its own `CodingKeys` and an init that defaults every
  /// optional to `nil`.
  ///
  /// `CodingKeys` is not optional here: PostgREST's encoder sets no key strategy, so without it an
  /// insert would send `isDone` while a filter on the same column sends `is_done`. Nor is the init
  /// — the memberwise init of a `public` struct is internal, and a partial update would otherwise
  /// have to spell out `nil` for every column it leaves alone.
  static func writeShape(
    named name: String,
    access: String,
    fields: [(property: StoredProperty, type: String)]
  ) -> String {
    var lines: [String] = ["  \(access)struct \(name): Encodable, Sendable {"]

    for field in fields {
      lines.append("    \(access)var \(field.property.name): \(field.type)")
    }

    if let codingKeys = codingKeys(for: fields.map(\.property), indent: "    ") {
      lines.append("")
      lines.append(codingKeys)
    }

    let parameters =
      fields
      .map { "\($0.property.name): \($0.type)\($0.type.hasSuffix("?") ? " = nil" : "")" }
      .joined(separator: ", ")
    lines.append("")
    lines.append("    \(access)init(\(parameters)) {")
    for field in fields {
      lines.append("      self.\(field.property.name) = \(field.property.name)")
    }
    lines.append("    }")
    lines.append("  }")
    return lines.joined(separator: "\n")
  }
}
