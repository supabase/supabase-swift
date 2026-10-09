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
    /// The members of the relation's `Columns` extension: its computed fields and relationships.
    var computed: [ComputedPlan] = []
  }

  struct ComputedPlan {
    /// As spelled in source, backticks included.
    var name: String
    /// The function name, which PostgREST addresses the member by.
    var function: String
    var kind: Kind

    enum Kind {
      case field(SwiftType)
      case toOne(target: String)
      case toMany(target: String)
    }
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
    relations = []
    enums = []
    schemas = []
    for schema in model.schemas where schema != "public" {
      let typeName = Self.unshadowed(
        Naming.typeName(schema), suffix: "Schema", label: "schema \(schema)", notes: &notes)
      schemas.append(SchemaPlan(name: schema, typeName: typeName))
    }

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
      let base = Self.unshadowed(
        Naming.typeName(prefix + declaration.name.name), suffix: declaration.suffix,
        label: declaration.label, notes: &notes)
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

    let relationTypeNames = Dictionary(
      uniqueKeysWithValues: zip(model.relations.map(\.name), typeNames))
    for index in relations.indices {
      relations[index].computed = computedMembers(
        of: relations[index], relationTypeNames: relationTypeNames, enumTypeNames: enumTypeNames)
    }
  }

  /// The computed fields and relationships of `plan`, from the functions whose only argument is
  /// its row type.
  ///
  /// A function belongs to the typed API only when PostgREST would resolve it from the relation's
  /// own schema, which is the schema `@Table` queries: so one in another schema is skipped. One
  /// named like a column is skipped too, because PostgREST resolves the column first; that compares
  /// Postgres names, not Swift ones. Every skip leaves a note.
  private mutating func computedMembers(
    of plan: RelationPlan,
    relationTypeNames: [QualifiedName: String],
    enumTypeNames: [Int: String]
  ) -> [ComputedPlan] {
    let columnNames = Set(plan.relation.columns.map(\.name))
    var members: [(function: DatabaseModel.Function, kind: ComputedPlan.Kind)] = []
    for function in plan.relation.functions {
      let label = "function \(function.name.schema).\(function.name.name)(\(function.signature))"
      func skip(_ reason: String) { notes.append("\(label) is not generated: \(reason)") }

      if function.name.schema != plan.relation.name.schema {
        skip("it is not in the schema of \(plan.relation.name.schema).\(plan.relation.name.name)")
      } else if columnNames.contains(function.name.name) {
        skip("\(plan.relation.name.name) has a column of the same name, which PostgREST resolves")
      } else if function.returnsRow {
        guard let target = function.returnRelation.flatMap({ relationTypeNames[$0] }) else {
          let target = function.returnRelation.map { "\($0.schema).\($0.name)" } ?? "unknown"
          skip("it returns \(target), which is not generated")
          continue
        }
        // `ROWS 1` is how PostgREST tells a set-returning function that returns one row.
        let isToOne = !function.isSetReturning || function.rows == 1
        members.append((function, isToOne ? .toOne(target: target) : .toMany(target: target)))
      } else if function.isSetReturning {
        skip("it returns a set of a scalar type, which PostgREST cannot select as a field")
      } else if let type = function.returnType,
        !(type.schema == "pg_catalog" && ["void", "record"].contains(type.name))
      {
        members.append(
          (
            function,
            .field(
              scalarType(
                schema: type.schema, name: type.name, enumID: function.returnEnumID,
                subject: "\(label) returns the type", enumTypeNames: enumTypeNames))
          )
        )
      } else {
        skip("it returns \(function.returnType?.name ?? "an unknown type"), not a value")
      }
    }

    // A computed member lives in `Columns` next to one `let` per column.
    let taken = Set(plan.properties.map(\.name))
    let bases = members.map { member in
      let base = Naming.propertyName(member.function.name.name)
      let bare = Naming.unescaped(base)
      guard taken.contains(base) || Naming.columnsMembers.contains(bare) else { return base }
      var renamed = Naming.identifier(bare + "Computed")
      if taken.contains(renamed) { renamed = Self.numbered(renamed, avoiding: taken) }
      notes.append(
        "function \(member.function.name.schema).\(member.function.name.name) is named "
          + "\(renamed): Columns of \(plan.relation.name.schema).\(plan.relation.name.name) "
          + "already has \(bare)")
      return renamed
    }
    let names = numberingRepeats(
      of: bases, taken: taken, kind: "member",
      labels: members.map { "function \($0.function.name.schema).\($0.function.name.name)" })
    return zip(members, names).map {
      ComputedPlan(name: $1, function: $0.function.name.name, kind: $0.kind)
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

  /// One case per value, in declaration order. The raw value keeps the exact label.
  private mutating func members(of type: DatabaseModel.EnumType) -> [EnumPlan.Member] {
    let label = "enum \(type.name.schema).\(type.name.name) value"
    let bases = type.values.map { value in
      let base = Naming.propertyName(value)
      let bare = Naming.unescaped(base)
      guard Naming.enumMembers.contains(bare) else { return base }
      let renamed = Naming.identifier(bare + "Case")
      notes.append("\(label) \(value) is named \(renamed): the enum reserves \(bare)")
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
  /// back unchanged, so generation never stops at one column. A computed field's return type
  /// follows the same rule.
  private mutating func swiftType(
    of column: DatabaseModel.Column,
    qualified: String,
    enumTypeNames: [Int: String]
  ) -> SwiftType {
    let type = scalarType(
      schema: column.typeSchema, name: column.format, enumID: column.enumID,
      subject: "\(qualified) has the type", enumTypeNames: enumTypeNames)
    return column.isNullable ? .optional(type) : type
  }

  /// The Swift type of a Postgres type, `name` being `_text` for an array of `text`. `subject`
  /// starts the note when the type is not mapped.
  private mutating func scalarType(
    schema: String,
    name: String,
    enumID: Int?,
    subject: String,
    enumTypeNames: [Int: String]
  ) -> SwiftType {
    let isArray = name.hasPrefix("_")
    let element = isArray ? String(name.dropFirst()) : name
    let scalar: String
    if let enumTypeName = enumID.flatMap({ enumTypeNames[$0] }) {
      scalar = enumTypeName
    } else if let mapped = schema == "pg_catalog" ? Self.scalarTypes[element] : nil {
      scalar = mapped
    } else if element == "citext" {
      // An extension type, so its schema is wherever the extension was installed.
      scalar = "String"
    } else {
      scalar = "JSONValue"
      notes.append(
        "\(subject) \(schema).\(element), which is not mapped; it is decoded as JSONValue")
    }
    return isArray ? .array(.named(scalar)) : .named(scalar)
  }
}

extension FilePlan {
  /// The generated file: one `enum` per enum type and one `@Table` struct per relation,
  /// formatted, ending in one newline.
  func render(accessControl: Options.AccessControl) throws -> String {
    let access: DeclModifierListSyntax =
      accessControl == .public ? [DeclModifierSyntax(name: .keyword(.public))] : []
    let usesFoundation = relations.contains { relation in
      relation.properties.contains { $0.type.usesFoundation }
        || relation.computed.contains {
          if case .field(let type) = $0.kind { type.usesFoundation } else { false }
        }
    }

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
        try EnumDeclSyntax(
          """
          \(access) enum \(TokenSyntax.identifier(type.typeName)): String, Codable, Hashable, \
          Sendable, PostgrestFilterValue
          """
        ) {
          for member in type.members {
            let name = TokenSyntax.identifier(member.name)
            if Naming.unescaped(member.name) == member.value {
              DeclSyntax("case \(name)")
            } else {
              DeclSyntax("case \(name) = \(StringLiteralExprSyntax(content: member.value))")
            }
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

        if !relation.computed.isEmpty {
          let type = TokenSyntax.identifier(relation.typeName)
          try ExtensionDeclSyntax("extension \(type).Columns") {
            for member in relation.computed {
              let name = TokenSyntax.identifier(member.name)
              let literal = StringLiteralExprSyntax(content: member.function)
              switch member.kind {
              case .field(let valueType):
                DeclSyntax(
                  "\(access) var \(name): PostgrestComputedField<\(type), \(valueType.syntax)> { .init(\(literal)) }"
                )
              case .toOne(let target):
                DeclSyntax(
                  "\(access) var \(name): PostgrestToOneRelation<\(type), \(TokenSyntax.identifier(target))> { .init(\(literal)) }"
                )
              case .toMany(let target):
                DeclSyntax(
                  "\(access) var \(name): PostgrestToManyRelation<\(type), \(TokenSyntax.identifier(target))> { .init(\(literal)) }"
                )
              }
            }
          }
          .with(\.leadingTrivia, .newlines(2))
        }
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

extension FilePlan {
  /// `base`, or `base` with `suffix` and a note when it would shadow a type the generated code
  /// uses.
  fileprivate static func unshadowed(
    _ base: String, suffix: String, label: String, notes: inout [String]
  ) -> String {
    let bare = Naming.unescaped(base)
    guard Naming.referencedTypes.contains(bare) else { return base }
    let renamed = Naming.identifier(bare + suffix)
    notes.append(
      "\(label) is named \(renamed): \(bare) would shadow a type the generated code uses")
    return renamed
  }
}
