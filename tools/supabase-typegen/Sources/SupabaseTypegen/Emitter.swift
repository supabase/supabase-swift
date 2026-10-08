//
//  Emitter.swift
//  SupabaseTypegen
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import SwiftBasicFormat
import SwiftFormat
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder

/// Everything the generated file declares, with every Swift name decided.
///
/// ``init(_:)`` makes every naming decision and collects the notes; ``render(accessControl:)``
/// turns the plan into source and makes none.
struct FilePlan {
  /// The caseless enums standing for the selected schemas other than `public`, sorted by name.
  var schemas: [SchemaPlan]
  /// The enum types, by schema, then name.
  var enums: [EnumPlan]
  /// In the model's order: schema, then name.
  var relations: [RelationPlan]
  /// One line each, for standard error: renames and types not mapped.
  var notes: [String] = []

  struct SchemaPlan {
    var name: String
    var typeName: String
  }

  struct EnumPlan {
    var type: DatabaseModel.EnumType
    var typeName: String
    var members: [Member]

    struct Member {
      /// As spelled in source, backticks included.
      var name: String
      /// The Postgres label.
      var value: String
    }
  }

  struct RelationPlan {
    var relation: DatabaseModel.Relation
    var typeName: String
    /// The ``SchemaPlan/typeName`` of the relation's schema, or `nil` for `public`.
    var schemaTypeName: String?
    var properties: [PropertyPlan]
    /// Whether `@Table` gets `readOnly: true`: a relation that cannot be written to.
    var readOnly: Bool
  }

  struct PropertyPlan {
    var column: DatabaseModel.Column
    /// As spelled in source, backticks included.
    var name: String
    /// The argument of `@Column`, or `nil` when `@Table` derives the column name from ``name``.
    var columnAttribute: String?
    var type: SwiftType
    /// `@PrimaryKey`, `@Generated` and `@Default`, without the `@`, in that order.
    var markers: [String]
  }

}

/// A Swift type the generator writes for a column.
indirect enum SwiftType: Equatable {
  case named(String)
  case array(SwiftType)
  case optional(SwiftType)

  var syntax: TypeSyntax {
    switch self {
    case .named(let name): TypeSyntax(IdentifierTypeSyntax(name: .identifier(name)))
    case .array(let element): TypeSyntax(ArrayTypeSyntax(element: element.syntax))
    case .optional(let wrapped): TypeSyntax(OptionalTypeSyntax(wrappedType: wrapped.syntax))
    }
  }

  /// Whether the type needs `Foundation`.
  var usesFoundation: Bool {
    switch self {
    case .named(let name): ["Date", "Decimal", "UUID"].contains(name)
    case .array(let inner), .optional(let inner): inner.usesFoundation
    }
  }
}

extension FilePlan {
  init(_ model: DatabaseModel) throws(DataError) {
    schemas = model.schemas.filter { $0 != "public" }
      .map { SchemaPlan(name: $0, typeName: Naming.typeName($0)) }
    relations = []
    enums = []

    // The enums of the selected schemas, and any other enum a generated column uses.
    let usedEnums = Set(model.relations.flatMap { $0.columns.compactMap(\.enumID) })
    let enumTypes = model.enums.values
      .filter { model.schemas.contains($0.name.schema) || usedEnums.contains($0.id) }
      .sorted { $0.name < $1.name }

    // Relations first, so an enum never renames a relation.
    let declarations: [(name: QualifiedName, label: String, suffix: String)] =
      model.relations.map { ($0.name, "\($0.name.schema).\($0.name.name)", "Table") }
      + enumTypes.map { ($0.name, "enum \($0.name.schema).\($0.name.name)", "Enum") }

    // Every top-level declaration, keyed by its Swift name. Same-schema declarations that convert
    // to the same name are told apart with a number; a clash that crosses schemas is an error,
    // because no suffix would tell the reader which schema each type belongs to.
    // `namespace` is the declaration's schema, or `nil` for a schema's own enum.
    var owners: [String: [(namespace: String?, label: String)]] = [:]
    for schema in schemas {
      owners[schema.typeName, default: []].append((nil, "schema \(schema.name)"))
    }
    var bases: [String] = []
    for declaration in declarations {
      let schema = declaration.name.schema
      let prefix = schema == "public" ? "" : schema + "_"
      var base = Naming.typeName(prefix + declaration.name.name)
      if Naming.referencedTypes.contains(Naming.unescaped(base)) {
        let renamed = Naming.identifier(Naming.unescaped(base) + declaration.suffix)
        notes.append(
          "\(declaration.label) is named \(renamed): \(Naming.unescaped(base)) would shadow a type "
            + "the generated code uses")
        base = renamed
      }
      bases.append(base)
      owners[base, default: []].append((schema, declaration.label))
    }
    let clashes = owners.filter { _, owners in
      owners.count > 1
        && (owners.contains { $0.namespace == nil } || Set(owners.map(\.namespace)).count > 1)
    }
    if !clashes.isEmpty {
      throw DataError(
        description: clashes.sorted { $0.key < $1.key }.map { name, owners in
          "\(owners.map(\.label).sorted().joined(separator: " and ")) both become the Swift type "
            + name
        }.joined(separator: "\n")
      )
    }

    let typeNames = numberingRepeats(
      of: bases, taken: Set(owners.keys), kind: "type", labels: declarations.map(\.label))
    let enumTypeNames = Dictionary(
      uniqueKeysWithValues: zip(enumTypes.map(\.id), typeNames.dropFirst(model.relations.count)))
    for (type, typeName) in zip(enumTypes, typeNames.dropFirst(model.relations.count)) {
      enums.append(EnumPlan(type: type, typeName: typeName, members: members(of: type)))
    }
    let schemaTypeNames = Dictionary(uniqueKeysWithValues: schemas.map { ($0.name, $0.typeName) })
    for (relation, typeName) in zip(model.relations, typeNames) {
      relations.append(
        RelationPlan(
          relation: relation,
          typeName: typeName,
          schemaTypeName: schemaTypeNames[relation.name.schema],
          properties: try properties(of: relation, enumTypeNames: enumTypeNames),
          readOnly: Self.isReadOnly(relation.kind)
        )
      )
    }
  }

  /// `bases`, with every repeat after the first numbered and noted. `labels` names each one in the
  /// note.
  private mutating func numberingRepeats(
    of bases: [String],
    taken: Set<String>,
    kind: String,
    labels: [String]
  ) -> [String] {
    var taken = taken.union(bases)
    var seen: Set<String> = []
    return zip(bases, labels).map { base, label in
      if seen.insert(base).inserted { return base }
      let name = Self.numbered(base, avoiding: taken)
      taken.insert(name)
      notes.append("\(label) is named \(name): another \(kind) is also named \(base)")
      return name
    }
  }

  /// One static member per value, in declaration order. The literal keeps the exact label.
  private mutating func members(of type: DatabaseModel.EnumType) -> [EnumPlan.Member] {
    let label = "enum \(type.name.schema).\(type.name.name) value"
    let bases = type.values.map { value in
      let base = Naming.propertyName(value)
      let bare = Naming.unescaped(base)
      guard Naming.enumMembers.contains(bare) else { return base }
      let renamed = Naming.identifier(bare + "Case")
      notes.append("\(label) \(value) is named \(renamed): the struct reserves \(bare)")
      return renamed
    }
    let names = numberingRepeats(
      of: bases, taken: [], kind: "value", labels: type.values.map { "\(label) \($0)" })
    return zip(names, type.values).map { EnumPlan.Member(name: $0, value: $1) }
  }

  private mutating func properties(
    of relation: DatabaseModel.Relation,
    enumTypeNames: [Int: String]
  ) throws(DataError) -> [PropertyPlan] {
    let qualified = "\(relation.name.schema).\(relation.name.name)"
    // `@PrimaryKey` on an Optional property is a macro error, so stop here and name the column.
    let nullableKeys = relation.columns.filter {
      $0.isNullable && relation.primaryKey.contains($0.name)
    }
    if !nullableKeys.isEmpty {
      throw DataError(
        description: nullableKeys.map {
          "\(qualified).\($0.name) is a primary key column but is nullable; "
            + "@PrimaryKey cannot mark an Optional property"
        }.joined(separator: "\n")
      )
    }
    let bases = relation.columns.map { column in
      let base = Naming.propertyName(column.name)
      let bare = Naming.unescaped(base)
      guard Naming.tableMembers.contains(bare) else { return base }
      let renamed = Naming.identifier(bare + "Column")
      notes.append("\(qualified).\(column.name) is named \(renamed): @Table reserves \(bare)")
      return renamed
    }
    let names = numberingRepeats(
      of: bases, taken: [], kind: "column",
      labels: relation.columns.map { "\(qualified).\($0.name)" })
    return zip(relation.columns, names).map { column, name in
      return PropertyPlan(
        column: column,
        name: name,
        columnAttribute: camelToSnakeCase(name) == column.name ? nil : column.name,
        type: swiftType(
          of: column, qualified: "\(qualified).\(column.name)", enumTypeNames: enumTypeNames),
        markers: Self.markers(of: column, isPrimaryKey: relation.primaryKey.contains(column.name))
      )
    }
  }

  /// A view is writable when PostgREST can insert or update through it (the model has already
  /// applied the `is_updatable` fallback). A materialized view and a foreign table are not.
  private static func isReadOnly(_ kind: DatabaseModel.Relation.Kind) -> Bool {
    switch kind {
    case .table: false
    case .view(let isInsertEnabled, let isUpdateEnabled): !(isInsertEnabled || isUpdateEnabled)
    case .materializedView, .foreignTable: true
    }
  }

  /// `@Generated` wins over `@Default`: a generated column is absent from `Draft`, so a default
  /// would add nothing, and `is_generated` columns carry their expression as `default_value`.
  static func markers(of column: DatabaseModel.Column, isPrimaryKey: Bool) -> [String] {
    var markers = isPrimaryKey ? ["PrimaryKey"] : []
    if column.isGenerated || column.identityGeneration == .always {
      markers.append("Generated")
    } else if column.hasDefault || column.identityGeneration == .byDefault {
      markers.append("Default")
    }
    return markers
  }

  /// `name2`, `name3`, … — the first one not in `taken`.
  private static func numbered(_ name: String, avoiding taken: Set<String>) -> String {
    let bare = Naming.unescaped(name)
    return (2...).lazy.map { Naming.identifier("\(bare)\($0)") }.first { !taken.contains($0) }
      ?? name
  }

  private static let scalarTypes: [String: String] = [
    "uuid": "UUID",
    "text": "String", "varchar": "String", "bpchar": "String", "char": "String",
    "bool": "Bool",
    "int2": "Int", "int4": "Int", "int8": "Int",
    "float4": "Double", "float8": "Double",
    "numeric": "Decimal",
    "timestamptz": "Date", "timestamp": "Date", "date": "Date",
    "json": "JSONValue", "jsonb": "JSONValue",
  ]

  /// A type with no mapping, such as a composite, a range, `bytea`, `interval` or `time`, is
  /// `JSONValue`, with a note: it decodes whatever PostgREST sends for the column and writes it
  /// back unchanged, so generation never stops at one column.
  private mutating func swiftType(
    of column: DatabaseModel.Column,
    qualified: String,
    enumTypeNames: [Int: String]
  ) -> SwiftType {
    let isArray = column.format.hasPrefix("_")
    let element = isArray ? String(column.format.dropFirst()) : column.format
    let scalar: String
    if let enumTypeName = column.enumID.flatMap({ enumTypeNames[$0] }) {
      scalar = enumTypeName
    } else if let mapped = column.typeSchema == "pg_catalog" ? Self.scalarTypes[element] : nil {
      scalar = mapped
    } else if element == "citext" {
      // An extension type, so its schema is wherever the extension was installed.
      scalar = "String"
    } else {
      scalar = "JSONValue"
      notes.append(
        "\(qualified) has the type \(column.typeSchema).\(element), which is not mapped; it is "
          + "decoded as JSONValue")
    }
    let type = isArray ? SwiftType.array(.named(scalar)) : .named(scalar)
    return column.isNullable ? .optional(type) : type
  }
}

extension FilePlan {
  /// The generated file: one struct per enum type and one `@Table` struct per relation,
  /// formatted, ending in one newline.
  func render(accessControl: Options.AccessControl) throws -> String {
    let access: DeclModifierListSyntax =
      accessControl == .public ? [DeclModifierSyntax(name: .keyword(.public))] : []
    let usesFoundation = relations.contains { $0.properties.contains { $0.type.usesFoundation } }

    let file = try SourceFileSyntax {
      // A public declaration needs its types' modules imported publicly under
      // `InternalImportsByDefault`, and `public import` compiles without it too.
      if usesFoundation {
        DeclSyntax("\(access) import Foundation")
      }
      DeclSyntax("\(access) import PostgrestMacros")

      for schema in schemas {
        try EnumDeclSyntax(
          "\(access) enum \(TokenSyntax.identifier(schema.typeName)): PostgrestSchema"
        ) {
          DeclSyntax("\(access) static let name = \(StringLiteralExprSyntax(content: schema.name))")
        }
        .with(\.leadingTrivia, .newlines(2))
      }

      for type in enums {
        let name = TokenSyntax.identifier(type.typeName)
        try StructDeclSyntax(
          """
          \(access) struct \(name): RawRepresentable, Codable, Hashable, Sendable,
            ExpressibleByStringLiteral, PostgrestFilterValue
          """
        ) {
          DeclSyntax("\(access) let rawValue: String")
          DeclSyntax("\(access) init(rawValue: String) { self.rawValue = rawValue }")
          DeclSyntax("\(access) init(stringLiteral value: String) { self.init(rawValue: value) }")
          for (index, member) in type.members.enumerated() {
            DeclSyntax(
              """
              \(access) static let \(TokenSyntax.identifier(member.name)): \(name) = \
              \(StringLiteralExprSyntax(content: member.value))
              """
            )
            .with(\.leadingTrivia, index == 0 ? .newlines(2) : .newline)
          }
        }
        .with(\.leadingTrivia, .newlines(2))
      }

      for relation in relations {
        try StructDeclSyntax(
          """
          \(tableAttribute(relation))
          \(access) struct \(TokenSyntax.identifier(relation.typeName))
          """
        ) {
          for property in relation.properties {
            let attributes = attributes(of: property)
            let name = TokenSyntax.identifier(property.name)
            DeclSyntax("\(attributes) \(access) var \(name): \(property.type.syntax)")
          }
        }
        .with(\.leadingTrivia, .newlines(2))
      }
    }

    var output = ""
    try SwiftFormatter(configuration: Self.formatConfiguration).format(
      source: file.formatted().description,
      assumingFileURL: nil,
      selection: .infinite,
      to: &output
    )
    return output
  }

  private func attributes(of property: PropertyPlan) -> AttributeListSyntax {
    var attributes = AttributeListSyntax(property.markers.map { .attribute("@\(raw: $0)") })
    if let column = property.columnAttribute {
      attributes.append(.attribute("@Column(\(StringLiteralExprSyntax(content: column)))"))
    }
    return attributes
  }

  private func tableAttribute(_ relation: RelationPlan) -> AttributeSyntax {
    let name = StringLiteralExprSyntax(content: relation.relation.name.name)
    let readOnly = relation.readOnly ? ", readOnly: true" : ""
    guard let schema = relation.schemaTypeName else {
      return "@Table(\(name)\(raw: readOnly))"
    }
    return "@Table(\(name), schema: \(TokenSyntax.identifier(schema)).self\(raw: readOnly))"
  }

  /// Built in rather than read from a `.swift-format` file, so every machine prints the same file.
  private static var formatConfiguration: Configuration {
    var configuration = Configuration()
    configuration.indentation = .spaces(2)
    configuration.lineLength = 100
    return configuration
  }
}
