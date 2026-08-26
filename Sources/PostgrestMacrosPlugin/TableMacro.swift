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
      context.error("@Table can only be applied to a struct", at: node)
      return []
    }
    if let relationship = declaration.postgrestRelationshipAttribute() {
      context.error(
        "@Relationship belongs on a @SelectionOf type, not on @Table",
        at: relationship
      )
      return []
    }
    if declaration.postgrestDiagnoseUnannotatedProperties(macro: "@Table", in: context) {
      return []
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
    // The one thing `@PrimaryKey` uniquely does. Without this the marker is inert: after the key
    // stopped gating `Draft` optionality and stopped being filtered out of `Update`, writing it or
    // omitting it expanded byte-for-byte the same. Emitted only when a key is declared, and the
    // `PostgrestKeyedRelation` conformance below rides on the same condition — the requirement has
    // no default, so a keyless relation does not conform, which is what withholds the
    // derived-conflict-target `upsert` from it at compile time.
    let keyColumns = properties.filter(\.isPrimaryKey).map(\.columnName)
    if !keyColumns.isEmpty {
      let list = keyColumns.map { "\"\($0)\"" }.joined(separator: ", ")
      body.append("  \(access)static let primaryKeyColumns: [String] = [\(list)]")
    }
    if let codingKeys = codingKeys(for: properties) {
      body.append(codingKeys)
    }
    if !arguments.readOnly {
      // `Draft` carries every column, and a column is optional exactly when the database can
      // fill it in: it is nullable, or it has a default. Being the primary key is not one of the
      // reasons — `postgres-meta`, which generates supabase-js's types from the same column
      // metadata, computes `is_nullable || is_identity || default_value !== null` and never
      // consults the key. `@Default` already carries what `is_identity || default_value !== null`
      // means, so a generated key is spelled `@PrimaryKey @Default var id: Int` and a natural one
      // — including each half of a compound key — is required, which is what makes a join table
      // insertable and an incomplete key a compile error rather than a 400.
      //
      // There is no matching `Update` shape. An update names the columns it writes, and a row
      // type cannot say that: one optional field would have to mean both "not assigned" and
      // "assigned null", so a nullable column could never be cleared. `PostgrestUpdate` builds
      // the assignments from this type's key paths instead, and `columnName(for:)` above is all
      // it needs from the macro. Targeting stays a separate concern — the caller filters the
      // mutation — so the key is assignable like any other column.
      body.append(
        writeShape(
          named: "Draft",
          access: access,
          fields: properties.map {
            ($0, $0.isOptional || $0.hasDefault ? $0.optionalType : $0.type)
          }
        )
      )
    }

    let clause = inheritanceClause(
      wanted: wantedConformances(arguments, hasPrimaryKey: !keyColumns.isEmpty),
      missing: protocols
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

  // MARK: Generation

  /// The protocols `@Table` conforms the annotated type to.
  ///
  /// `Decodable` is in the list and `Encodable` is not: rows are decoded from responses, and writes
  /// go out through the `Encodable` `Draft` shape.
  ///
  /// Keyed and writable are independent axes: a view Postgres reports a key for is keyed and still
  /// read-only, and an append-only table is writable with no key at all.
  static func wantedConformances(_ arguments: Arguments, hasPrimaryKey: Bool) -> [String] {
    [
      "Decodable",
      "Sendable",
      "PostgrestRelation",
      hasPrimaryKey ? "PostgrestKeyedRelation" : nil,
      arguments.readOnly ? nil : "PostgrestWritableRelation",
    ].compactMap { $0 }
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
      "  \(access)static func columnName(for keyPath: PartialKeyPath<Self>) -> String {",
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
      // The default follows the *generated* parameter type, not the property's own. In `Update`
      // every column is optional even when the property is not, so testing the property here would
      // drop the default that makes a partial update possible.
      .map { "\($0.property.name): \($0.type)\(postgrestIsOptionalType($0.type) ? " = nil" : "")" }
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
