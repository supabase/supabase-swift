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
///   `extension Todo: _PostgrestWritableRelation` alone reports "does not conform to inherited
///   protocol _PostgrestRelation", with no note saying which requirement is missing.
public struct TableMacro: ExtensionMacro {
  struct Arguments {
    var name: String
    var schema: ExprSyntax?
    var readOnly: Bool
  }

  static func arguments(from node: AttributeSyntax) -> Arguments {
    var name = ""
    var schema: ExprSyntax?
    var readOnly = false
    for argument in node.arguments?.as(LabeledExprListSyntax.self) ?? [] {
      switch argument.label?.text {
      case nil:
        name = argument.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue ?? ""
      case "schema":
        schema = argument.expression
      case "readOnly":
        readOnly = argument.expression.as(BooleanLiteralExprSyntax.self)?.literal.text == "true"
      default:
        break
      }
    }
    return Arguments(name: name, schema: schema, readOnly: readOnly)
  }

  static func schemaType(of expression: ExprSyntax) -> String? {
    guard let access = expression.as(MemberAccessExprSyntax.self),
      access.declName.baseName.tokenKind == .keyword(.self),
      let base = access.base
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
      context.error("@Table can only be applied to a struct", at: node)
      return []
    }
    if let attribute = declaration.postgrestSelectionOnlyAttribute() {
      context.error(
        "@\(attribute.attributeName.trimmedDescription) belongs on a @SelectionOf type, not on @Table",
        at: attribute
      )
      return []
    }
    if declaration.postgrestDiagnoseUnannotatedProperties(macro: "@Table", in: context) {
      return []
    }
    if declaration.postgrestDiagnoseMarkerPlacement(in: context) {
      return []
    }
    let arguments = arguments(from: node)
    var schema = "PostgREST._PublicSchema"
    if let expression = arguments.schema {
      guard let written = schemaType(of: expression) else {
        context.error("schema: needs a schema type, as in `PrivateSchema.self`", at: expression)
        return []
      }
      schema = written
    }
    let access = declaration.postgrestAccessLevel
    let properties = declaration.postgrestStoredProperties()

    var body: [String] = [
      "  \(access)static let relationName = \"\(postgrestEscaped(arguments.name))\"",
      "  \(access)typealias Schema = \(schema)",
      "  \(access)static let selectString = \"*\"",
      columnsNamespace(access: access, type: type.trimmedDescription, properties: properties),
    ]
    let keyColumns = properties.filter(\.isPrimaryKey).map(\.columnName)
    if !keyColumns.isEmpty {
      let list = keyColumns.map { "\"\(postgrestEscaped($0))\"" }.joined(separator: ", ")
      body.append("  \(access)static let primaryKeyColumns: [String] = [\(list)]")
    }
    if let codingKeys = codingKeys(for: properties) {
      body.append(codingKeys)
    }
    if !arguments.readOnly {
      body.append(
        writeShape(
          named: "Draft",
          access: access,
          fields: properties.filter { !$0.isGenerated }.map {
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

  /// The protocols `@Table` conforms the annotated type to.
  ///
  /// `Decodable` is in the list and `Encodable` is not: rows are decoded from responses, and a
  /// write encodes something other than a row — the generated `Draft` shape, or a
  /// `_PostgrestUpdate` built from this type's key paths.
  ///
  /// Keyed and writable are independent axes: a view Postgres reports a key for is keyed and still
  /// read-only, and an append-only table is writable with no key at all.
  static func wantedConformances(_ arguments: Arguments, hasPrimaryKey: Bool) -> [String] {
    [
      "Decodable",
      "Sendable",
      "_PostgrestRelation",
      hasPrimaryKey ? "_PostgrestKeyedRelation" : nil,
      arguments.readOnly ? nil : "_PostgrestWritableRelation",
    ].compactMap { $0 }
  }

  /// The column namespace: one stored property per column. A computed property has nothing to
  /// land on here — it is simply not one of `properties`.
  ///
  /// An optional property gets a `_PostgrestNullableColumn` carrying its **wrapped** type, so
  /// `var dueDate: Date?` emits `_PostgrestNullableColumn<Todo, Date>`. A `@Generated` property
  /// gets a `_PostgrestGeneratedColumn` with the nullability spelled out, which is what keeps it
  /// out of `_PostgrestUpdate`.
  ///
  /// The explicit `init()` is required: a `public` struct's memberwise initializer is internal,
  /// so `Columns()` would not resolve from another module.
  static func columnsNamespace(
    access: String,
    type: String,
    properties: [StoredProperty]
  ) -> String {
    var lines = ["  \(access)struct Columns: Sendable {"]
    for property in properties {
      let column: String
      if property.isGenerated {
        let nullability = property.isOptional ? "_PostgrestNullable" : "_PostgrestNotNull"
        column = "_PostgrestGeneratedColumn<\(type), \(property.unwrappedType), \(nullability)>"
      } else {
        let kind = property.isOptional ? "_PostgrestNullableColumn" : "_PostgrestColumn"
        column = "\(kind)<\(type), \(property.unwrappedType)>"
      }
      let name = postgrestEscaped(property.columnName)
      lines.append("    \(access)let \(property.name) = \(column)(\"\(name)\")")
    }
    lines.append("")
    lines.append("    \(access)init() {}")
    lines.append("  }")
    lines.append("")
    lines.append("  \(access)static let columns = Columns()")
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
