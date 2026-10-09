//
//  DatabaseModel.swift
//  SupabaseTypegen
//
//  Created by Guilherme Souza on 08/10/26.
//

/// What the emitter reads: the relations of the selected schemas with their columns, keys and
/// candidate computed members, and every enum type of the document.
///
/// Every collection is in a deterministic order that does not depend on the document's order:
/// relations by schema then name, columns by `ordinal_position`, functions by schema, name, then
/// signature.
struct DatabaseModel: Equatable {
  /// The selected schemas, sorted.
  var schemas: [String]
  var relations: [Relation]
  /// Every enum type in the document, keyed by type id. A column may use an enum of a schema that
  /// is not selected.
  var enums: [Int: EnumType]

  struct Relation: Equatable {
    var name: QualifiedName
    var kind: Kind
    /// In `ordinal_position` order.
    var columns: [Column]
    /// The names of the primary key columns, in `ordinal_position` order. Empty for a relation
    /// without one, which includes every view.
    var primaryKey: [String]
    /// Functions whose single input argument is this relation's row type: the candidates for its
    /// computed fields and computed relationships. Not filtered further; a function in another
    /// schema or named like a column is still here.
    var functions: [Function]

    enum Kind: Equatable {
      case table
      /// `isInsertEnabled` and `isUpdateEnabled` fall back to `is_updatable` when the document
      /// predates them.
      case view(isInsertEnabled: Bool, isUpdateEnabled: Bool)
      case materializedView
      case foreignTable
    }
  }

  struct Column: Equatable {
    var name: String
    /// The Postgres type name, e.g. `int8`, `timestamptz`, or `_text` for `text[]`.
    var format: String
    /// The schema of `format`'s type.
    var typeSchema: String
    /// The id of the enum type of the column, or of its elements for an array column.
    var enumID: Int?
    var hasDefault: Bool
    var identityGeneration: IdentityGeneration?
    var isGenerated: Bool
    var isNullable: Bool
  }

  struct Function: Equatable {
    var name: QualifiedName
    /// The input argument types, e.g. `public.books`. Tells overloads apart.
    var signature: String
    var returnTypeID: Int
    /// The schema and name of the return type, or `nil` when the document does not list it.
    var returnType: QualifiedName?
    /// The id of the enum type returned, or of its elements for an array, or `nil` when it is not
    /// an enum.
    var returnEnumID: Int?
    /// Whether the function returns the row type of a relation.
    var returnsRow: Bool
    /// The relation whose row type is returned, or `nil` when the document does not list it.
    var returnRelation: QualifiedName?
    var isSetReturning: Bool
    /// The `ROWS` estimate; `ROWS 1` on a set-returning function marks a to-one relationship.
    var rows: Int?
  }

  struct EnumType: Equatable {
    var id: Int
    var name: QualifiedName
    /// In declaration order.
    var values: [String]
  }
}

struct QualifiedName: Hashable, Comparable {
  var schema: String
  var name: String

  static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.schema, lhs.name) < (rhs.schema, rhs.name)
  }
}

extension DatabaseModel {
  /// Indexes `metadata`, keeping the relations of `schemas`, or of every schema the document lists
  /// when `schemas` is empty.
  init(_ metadata: GeneratorMetadata, schemas: [String] = []) {
    let selected = Set(schemas.isEmpty ? metadata.schemas.map(\.name) : schemas)
    self.schemas = selected.sorted()

    let kinds: [(GeneratorMetadata.Relation, Relation.Kind)] =
      metadata.tables.map { ($0, .table) }
      + metadata.views.map { view in
        (
          GeneratorMetadata.Relation(id: view.id, schema: view.schema, name: view.name),
          .view(
            isInsertEnabled: view.isInsertEnabled ?? view.isUpdatable,
            isUpdateEnabled: view.isUpdateEnabled ?? view.isUpdatable
          )
        )
      }
      + metadata.materializedViews.map { ($0, .materializedView) }
      + metadata.foreignTables.map { ($0, .foreignTable) }

    let relationNames = Dictionary(
      kinds.map { ($0.0.id, QualifiedName(schema: $0.0.schema, name: $0.0.name)) },
      uniquingKeysWith: { first, _ in first }
    )
    let types = Dictionary(
      metadata.types.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    enums = types.compactMapValues { type in
      type.enums.isEmpty
        ? nil
        : EnumType(
          id: type.id, name: QualifiedName(schema: type.schema, name: type.name), values: type.enums
        )
    }
    let enumIDs = Dictionary(
      enums.values.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })

    let columnsByRelation = Dictionary(grouping: metadata.columns, by: \.tableId)
    let primaryKeysByRelation = Dictionary(grouping: metadata.primaryKeys, by: \.tableId)

    let inputModes: Set = ["in", "inout", "variadic"]
    var functionsByRelation: [Int: [Function]] = [:]
    for function in metadata.functions {
      let inputs = function.args.filter { inputModes.contains($0.mode) }
      guard inputs.count == 1, let relationID = types[inputs[0].typeId]?.typeRelationId else {
        continue
      }
      let returnType = types[function.returnTypeId]
      functionsByRelation[relationID, default: []].append(
        Function(
          name: QualifiedName(schema: function.schema, name: function.name),
          signature: function.identityArgumentTypes,
          returnTypeID: function.returnTypeId,
          returnType: returnType.map { QualifiedName(schema: $0.schema, name: $0.name) },
          returnEnumID: returnType.flatMap { type in
            let element = type.name.hasPrefix("_") ? String(type.name.dropFirst()) : type.name
            return enumIDs[QualifiedName(schema: type.schema, name: element)]
          },
          returnsRow: function.returnTypeRelationId != nil,
          returnRelation: function.returnTypeRelationId.flatMap { relationNames[$0] },
          isSetReturning: function.isSetReturningFunction,
          rows: function.prorows
        )
      )
    }

    // A document that lists one relation twice, say in both `tables` and `views`, keeps the first.
    var seen: Set<QualifiedName> = []
    relations =
      kinds
      .filter {
        selected.contains($0.0.schema)
          && seen.insert(QualifiedName(schema: $0.0.schema, name: $0.0.name)).inserted
      }
      .map { relation, kind in
        let columns = (columnsByRelation[relation.id] ?? [])
          .sorted { ($0.ordinalPosition, $0.name) < ($1.ordinalPosition, $1.name) }
        let positions = Dictionary(
          columns.map { ($0.name, $0.ordinalPosition) }, uniquingKeysWith: { first, _ in first })
        return Relation(
          name: QualifiedName(schema: relation.schema, name: relation.name),
          kind: kind,
          columns: columns.map { column in
            let element =
              column.format.hasPrefix("_") ? String(column.format.dropFirst()) : column.format
            return Column(
              name: column.name,
              format: column.format,
              typeSchema: column.typeSchema,
              enumID: enumIDs[QualifiedName(schema: column.typeSchema, name: element)],
              hasDefault: column.hasDefault,
              identityGeneration: column.identityGeneration,
              isGenerated: column.isGenerated,
              isNullable: column.isNullable
            )
          },
          primaryKey: (primaryKeysByRelation[relation.id] ?? []).map(\.name)
            .sorted { (positions[$0] ?? .max, $0) < (positions[$1] ?? .max, $1) },
          functions: (functionsByRelation[relation.id] ?? [])
            .sorted { ($0.name, $0.signature) < ($1.name, $1.signature) }
        )
      }
      .sorted { $0.name < $1.name }
  }
}
