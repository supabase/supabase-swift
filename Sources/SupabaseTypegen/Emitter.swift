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
  /// In the model's order: schema, then name.
  var relations: [RelationPlan]
  /// One line each, for standard error: renames and types not mapped yet.
  var notes: [String] = []

  struct SchemaPlan {
    var name: String
    var typeName: String
  }

  struct RelationPlan {
    var relation: DatabaseModel.Relation
    var typeName: String
    /// The ``SchemaPlan/typeName`` of the relation's schema, or `nil` for `public`.
    var schemaTypeName: String?
    var properties: [PropertyPlan]
  }

  struct PropertyPlan {
    var column: DatabaseModel.Column
    /// As spelled in source, backticks included.
    var name: String
    /// The argument of `@Column`, or `nil` when `@Table` derives the column name from ``name``.
    var columnAttribute: String?
    var type: SwiftType
  }

  /// Two declarations that would get the same Swift type name because of schema prefixing.
  struct TypeNameClash: Error, CustomStringConvertible {
    var description: String
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
  init(_ model: DatabaseModel) throws(TypeNameClash) {
    schemas = model.schemas.filter { $0 != "public" }
      .map { SchemaPlan(name: $0, typeName: Naming.typeName($0)) }
    relations = []

    // Every top-level declaration, keyed by its Swift name. Same-schema relations that convert to
    // the same name are told apart with a number; a clash that crosses schemas is an error,
    // because no suffix would tell the reader which schema each type belongs to.
    // `namespace` is the relation's schema, or `nil` for a schema's own enum.
    var owners: [String: [(namespace: String?, label: String)]] = [:]
    for schema in schemas {
      owners[schema.typeName, default: []].append((nil, "schema \(schema.name)"))
    }
    var relationBases: [String] = []
    for relation in model.relations {
      let qualified = "\(relation.name.schema).\(relation.name.name)"
      let prefix = relation.name.schema == "public" ? "" : relation.name.schema + "_"
      var base = Naming.typeName(prefix + relation.name.name)
      if Naming.referencedTypes.contains(Naming.unescaped(base)) {
        let renamed = Naming.identifier(Naming.unescaped(base) + "Table")
        notes.append(
          "\(qualified) is named \(renamed): \(Naming.unescaped(base)) would shadow a type the "
            + "generated code uses")
        base = renamed
      }
      relationBases.append(base)
      owners[base, default: []].append((relation.name.schema, qualified))
    }
    let clashes = owners.filter { _, owners in
      owners.count > 1
        && (owners.contains { $0.namespace == nil } || Set(owners.map(\.namespace)).count > 1)
    }
    if !clashes.isEmpty {
      throw TypeNameClash(
        description: clashes.sorted { $0.key < $1.key }.map { name, owners in
          "\(owners.map(\.label).sorted().joined(separator: " and ")) both become the Swift type "
            + name
        }.joined(separator: "\n")
      )
    }

    var typeNames = Set(owners.keys)
    var seen: Set<String> = []
    let schemaTypeNames = Dictionary(uniqueKeysWithValues: schemas.map { ($0.name, $0.typeName) })
    for (relation, base) in zip(model.relations, relationBases) {
      let qualified = "\(relation.name.schema).\(relation.name.name)"
      var typeName = base
      if !seen.insert(base).inserted {
        typeName = Self.numbered(base, avoiding: typeNames)
        typeNames.insert(typeName)
        notes.append("\(qualified) is named \(typeName): another relation is also named \(base)")
      }
      relations.append(
        RelationPlan(
          relation: relation,
          typeName: typeName,
          schemaTypeName: schemaTypeNames[relation.name.schema],
          properties: properties(of: relation, qualified: qualified, model: model)
        )
      )
    }
  }

  private mutating func properties(
    of relation: DatabaseModel.Relation,
    qualified: String,
    model: DatabaseModel
  ) -> [PropertyPlan] {
    let bases = relation.columns.map { column in
      let base = Naming.propertyName(column.name)
      let bare = Naming.unescaped(base)
      guard Naming.tableMembers.contains(bare) else { return base }
      let renamed = Naming.identifier(bare + "Column")
      notes.append("\(qualified).\(column.name) is named \(renamed): @Table reserves \(bare)")
      return renamed
    }
    var names = Set(bases)
    var seen: Set<String> = []
    return zip(relation.columns, bases).map { column, base in
      var name = base
      if !seen.insert(base).inserted {
        name = Self.numbered(base, avoiding: names)
        names.insert(name)
        notes.append(
          "\(qualified).\(column.name) is named \(name): another column is also named \(base)")
      }
      return PropertyPlan(
        column: column,
        name: name,
        columnAttribute: Naming.camelToSnakeCase(name) == column.name ? nil : column.name,
        type: swiftType(of: column, qualified: "\(qualified).\(column.name)", model: model)
      )
    }
  }

  /// `name2`, `name3`, … — the first one not in `taken`.
  private static func numbered(_ name: String, avoiding taken: Set<String>) -> String {
    let bare = Naming.unescaped(name)
    return (2...).lazy.map { Naming.identifier("\(bare)\($0)") }.first { !taken.contains($0) }
      ?? name
  }

  private static let scalarTypes: [String: String] = [
    "uuid": "UUID",
    "text": "String", "varchar": "String", "bpchar": "String",
    "bool": "Bool",
    "int2": "Int", "int4": "Int", "int8": "Int",
    "float4": "Double", "float8": "Double",
    "numeric": "Decimal",
    "timestamptz": "Date", "timestamp": "Date", "date": "Date",
    "json": "JSONValue", "jsonb": "JSONValue",
  ]

  private mutating func swiftType(
    of column: DatabaseModel.Column,
    qualified: String,
    model: DatabaseModel
  ) -> SwiftType {
    let isArray = column.format.hasPrefix("_")
    let element = isArray ? String(column.format.dropFirst()) : column.format
    var scalar: String
    if let id = column.enumID, let type = model.enums[id] {
      // ponytail: JSONValue until Task 4 generates the enum types.
      scalar = "JSONValue"
      notes.append(
        "\(qualified) has the enum type \(type.name.schema).\(type.name.name), which is not "
          + "generated yet; it is decoded as JSONValue")
    } else if let mapped = column.typeSchema == "pg_catalog" ? Self.scalarTypes[element] : nil {
      scalar = mapped
    } else if element == "citext" {
      // An extension type, so its schema is wherever the extension was installed.
      scalar = "String"
    } else {
      // ponytail: JSONValue until Task 4 settles the policy for unmapped types.
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
  /// The generated file: one `@Table` struct per relation, formatted, ending in one newline.
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

      for relation in relations {
        try StructDeclSyntax(
          """
          \(tableAttribute(relation))
          \(access) struct \(TokenSyntax.identifier(relation.typeName))
          """
        ) {
          for property in relation.properties {
            let attributes: AttributeListSyntax =
              if let column = property.columnAttribute {
                [.attribute("@Column(\(StringLiteralExprSyntax(content: column)))")]
              } else {
                []
              }
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

  private func tableAttribute(_ relation: RelationPlan) -> AttributeSyntax {
    let name = StringLiteralExprSyntax(content: relation.relation.name.name)
    guard let schema = relation.schemaTypeName else {
      return "@Table(\(name))"
    }
    return "@Table(\(name), schema: \(TokenSyntax.identifier(schema)).self)"
  }

  /// Built in rather than read from a `.swift-format` file, so every machine prints the same file.
  private static var formatConfiguration: Configuration {
    var configuration = Configuration()
    configuration.indentation = .spaces(2)
    configuration.lineLength = 100
    return configuration
  }
}
