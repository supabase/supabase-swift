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
  /// The row types of the functions that return `RETURNS TABLE` or `OUT` parameter rows, in the
  /// order of ``functions``.
  var functionResults: [RelationPlan] = []
  /// The methods of the `_PostgrestRpc` extension: one per callable overload, by schema, then
  /// name.
  var functions: [FunctionPlan] = []
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

  struct FunctionPlan {
    /// As spelled in source, backticks included.
    var name: String
    /// The function's name, which PostgREST addresses it by.
    var function: String
    /// The ``SchemaPlan/typeName`` of the function's schema, or `nil` for `public`.
    var schemaTypeName: String?
    /// Required parameters first, then the defaulted ones, each in name order.
    var parameters: [ParameterPlan]
    var result: Result

    enum Result {
      /// The rows of a relation or a function result type, filterable through its columns.
      case rows(String)
      /// One row, or `nil` when the function finds none.
      case row(String)
      case value(SwiftType)
      case nothing
    }
  }

  struct ParameterPlan {
    /// The argument label, backticks included, or `nil` for the whole body of a function whose
    /// sole parameter is an unnamed `json` or `jsonb`.
    var label: String?
    /// The name the method body reads the value by, when it differs from ``label``.
    var internalName: String?
    /// The Postgres parameter name.
    var argument: String
    var type: SwiftType
    /// Whether the parameter is `nil` by default, which leaves the argument out.
    var hasDefault: Bool

    /// The name the method body reads the value by.
    var variable: String { internalName ?? label ?? "body" }
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
indirect enum SwiftType: Equatable, Sendable {
  case named(String)
  /// A generic type with one argument, such as `_PostgresRange<Int>`.
  case generic(String, SwiftType)
  case array(SwiftType)
  case optional(SwiftType)

  var syntax: TypeSyntax {
    switch self {
    case .named(let name): TypeSyntax(IdentifierTypeSyntax(name: .identifier(name)))
    case .generic(let name, let argument):
      TypeSyntax(
        IdentifierTypeSyntax(
          name: .identifier(name),
          genericArgumentClause: GenericArgumentClauseSyntax(
            arguments: [GenericArgumentSyntax(argument: .type(argument.syntax))])))
    case .array(let element): TypeSyntax(ArrayTypeSyntax(element: element.syntax))
    case .optional(let wrapped): TypeSyntax(OptionalTypeSyntax(wrappedType: wrapped.syntax))
    }
  }

  /// Whether the type needs `Foundation`.
  var usesFoundation: Bool {
    switch self {
    case .named(let name): FilePlan.foundationScalarTypes.values.contains(name)
    case .generic(_, let inner), .array(let inner), .optional(let inner): inner.usesFoundation
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

    let callables = callableOverloads(of: model)
    let relationEnums = model.relations.flatMap {
      $0.columns.compactMap(\.enumID) + $0.functions.compactMap(\.returnEnumID)
    }
    let functionEnums = callables.flatMap { callable -> [Int] in
      let overload = callable.overload
      let types: [DatabaseModel.RpcType?] =
        overload.arguments.map(\.type) + [overload.returnType]
        + (overload.columns ?? []).map(\.type)
      return types.compactMap { $0?.enumID }
    }
    let usedEnums = Set(relationEnums + functionEnums)
    let enumTypes = model.enums.values
      .filter { model.schemas.contains($0.name.schema) || usedEnums.contains($0.id) }
      .sorted { $0.name < $1.name }

    // Relations first, so an enum never renames a relation.
    let declarations: [(name: QualifiedName, label: String, suffix: String)] =
      model.relations.map { ($0.name, "\($0.name.schema).\($0.name.name)", "Table") }
      + enumTypes.map { ($0.name, "enum \($0.name.schema).\($0.name.name)", "Enum") }
      + callables.filter { $0.returnsResultRows }.map {
        (
          QualifiedName(schema: $0.function.name.schema, name: $0.function.name.name + "_row"),
          "\($0.label) result", "Row"
        )
      }

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

    let typeNames = numberRepeats(
      in: bases, avoiding: Set(owners.keys), kind: "type", labels: declarations.map(\.label))
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
      zip(model.relations.map(\.name), typeNames), uniquingKeysWith: { first, _ in first })
    for index in relations.indices {
      relations[index].computed = computedMembers(
        of: relations[index], relationTypeNames: relationTypeNames, enumTypeNames: enumTypeNames)
    }

    var resultTypeNames = typeNames.dropFirst(model.relations.count + enumTypes.count)
      .makeIterator()
    for callable in callables {
      var resultTypeName: String?
      if callable.returnsResultRows, let typeName = resultTypeNames.next() {
        let result = DatabaseModel.Relation(
          name: callable.function.name,
          kind: .functionResult,
          columns: (callable.overload.columns ?? []).map { column in
            DatabaseModel.Column(
              name: column.name, format: column.type?.name.name ?? "",
              typeSchema: column.type?.name.schema ?? "", enumID: column.type?.enumID,
              hasDefault: false, identityGeneration: nil, isGenerated: false, isNullable: true)
          },
          primaryKey: [],
          functions: []
        )
        functionResults.append(
          RelationPlan(
            relation: result,
            typeName: typeName,
            schemaTypeName: schemaTypeNames[result.name.schema],
            properties: try properties(of: result, enumTypeNames: enumTypeNames),
            readOnly: true
          )
        )
        resultTypeName = typeName
      }
      functions.append(
        functionPlan(
          callable, resultTypeName: resultTypeName, relationTypeNames: relationTypeNames,
          enumTypeNames: enumTypeNames, schemaTypeNames: schemaTypeNames))
    }
    nameFunctions()
  }

  /// One overload the generator writes a method for.
  struct Callable {
    var function: DatabaseModel.RpcFunction
    var overload: DatabaseModel.RpcOverload
    /// Names the overload in notes, for example `function public.search(query text)`.
    var label: String
    /// Whether the function returns `RETURNS TABLE` or `OUT` parameter rows, which get a row
    /// type of their own.
    var returnsResultRows: Bool { !overload.returnsRelationRows && overload.columns != nil }
  }

  /// The overloads a method can call, in the model's order, with a note for each one left out.
  ///
  /// An overload PostgREST cannot resolve, one that takes a row, and one with an unnamed parameter
  /// other than a sole `json` or `jsonb` are left out. So is one that returns the rows of a
  /// relation the file does not declare. A computed field is left out without a note when it
  /// cannot be called, since its relation's `Columns` already covers it.
  private mutating func callableOverloads(of model: DatabaseModel) -> [Callable] {
    guard let functions = model.rpcFunctions else {
      notes.append(
        "the document has no rpcFunctions, so no function calls are generated; it needs "
          + "postgrest-typegen 0.5.0 or later")
      return []
    }
    let generated = Set(model.relations.map(\.name))
    var callables: [Callable] = []
    for function in functions {
      for overload in function.overloads {
        let signature = overload.arguments.map { argument in
          let type = argument.type?.name.name ?? "unknown"
          return argument.name.isEmpty ? type : "\(argument.name) \(type)"
        }.joined(separator: ", ")
        let label = "function \(function.name.schema).\(function.name.name)(\(signature))"
        let isBody =
          overload.arguments.count == 1 && overload.arguments[0].name.isEmpty
          && overload.arguments[0].type.map {
            $0.name.schema == "pg_catalog" && ["json", "jsonb"].contains($0.name.name)
          } == true
        let reason: String? =
          if let error = overload.error {
            error
          } else if overload.returnType == nil
            || overload.arguments.contains(where: { $0.type == nil })
            || overload.columns?.contains(where: { $0.type == nil }) == true
          {
            "its types are not in the document"
          } else if let row = overload.arguments.first(where: \.isRow) {
            "it takes a row of \(row.type?.name.name ?? "unknown"), which has no Encodable Swift type"
          } else if !isBody && overload.arguments.contains(where: \.name.isEmpty) {
            "it has an unnamed parameter, which PostgREST only passes as the whole body of a "
              + "function whose sole parameter is json or jsonb"
          } else if overload.returnsRelationRows,
            overload.returnRelation.map(generated.contains) != true
          {
            "it returns "
              + (overload.returnRelation.map { "\($0.schema).\($0.name)" } ?? "unknown")
              + ", which is not generated"
          } else {
            nil
          }
        if let reason {
          if !overload.isComputedField {
            notes.append("\(label) is not generated: \(reason)")
          }
          continue
        }
        callables.append(Callable(function: function, overload: overload, label: label))
      }
    }
    return callables
  }

  private mutating func functionPlan(
    _ callable: Callable,
    resultTypeName: String?,
    relationTypeNames: [QualifiedName: String],
    enumTypeNames: [Int: String],
    schemaTypeNames: [String: String]
  ) -> FunctionPlan {
    let overload = callable.overload
    let name = callable.function.name
    func swiftType(_ type: DatabaseModel.RpcType?, subject: String) -> SwiftType {
      let type = type!
      return scalarType(
        schema: type.name.schema, name: type.name.name, enumID: type.enumID,
        subject: "\(callable.label) \(subject)", enumTypeNames: enumTypeNames)
    }

    let result: FunctionPlan.Result
    if let resultTypeName {
      result = overload.isSetReturning ? .rows(resultTypeName) : .row(resultTypeName)
    } else if overload.returnsRelationRows, let target = overload.returnRelation,
      let typeName = relationTypeNames[target]
    {
      result = overload.isSetReturning ? .rows(typeName) : .row(typeName)
    } else if overload.returnType?.name == QualifiedName(schema: "pg_catalog", name: "void") {
      result = .nothing
    } else {
      let type = swiftType(overload.returnType, subject: "returns the type")
      result = .value(overload.isSetReturning ? .array(.optional(type)) : .optional(type))
    }

    let ordered =
      overload.arguments.filter { !$0.hasDefault } + overload.arguments.filter(\.hasDefault)
    var parameters: [ParameterPlan]
    if ordered.count == 1, ordered[0].name.isEmpty {
      parameters = [
        ParameterPlan(
          label: nil, argument: "",
          type: swiftType(ordered[0].type, subject: "takes the type"), hasDefault: false)
      ]
    } else {
      let labels = numberRepeats(
        in: ordered.map { Naming.propertyName($0.name) }, avoiding: [], kind: "parameter",
        labels: ordered.map { "\(callable.label) parameter \($0.name)" })
      parameters = zip(ordered, labels).map { argument, label in
        let type = swiftType(argument.type, subject: "parameter \(argument.name) has the type")
        return ParameterPlan(
          label: label,
          // `self` as a parameter would hide the `_PostgrestRpc` the method calls through.
          internalName: Naming.unescaped(label) == "self" ? "selfArgument" : nil,
          argument: argument.name,
          type: argument.hasDefault ? .optional(type) : type,
          hasDefault: argument.hasDefault
        )
      }
    }

    return FunctionPlan(
      name: "", function: name.name, schemaTypeName: schemaTypeNames[name.schema],
      parameters: parameters, result: result)
  }

  /// Names every method in ``functions``. Functions outside `public` carry their schema as a
  /// prefix. Overloads share a name and differ in their argument labels, the way PostgREST tells
  /// them apart; one that would repeat another method's name, labels and types is numbered.
  private mutating func nameFunctions() {
    let schemaNames = Dictionary(
      schemas.map { ($0.typeName, $0.name) }, uniquingKeysWith: { first, _ in first })
    var taken: Set<String> = []
    for index in functions.indices {
      let plan = functions[index]
      let schema = plan.schemaTypeName.flatMap { schemaNames[$0] } ?? "public"
      let qualified = "\(schema).\(plan.function)"
      var name = Naming.propertyName(
        (schema == "public" ? "" : schema + "_") + plan.function)
      let bare = Naming.unescaped(name)
      if Naming.rpcMembers.contains(bare) {
        name = Naming.identifier(bare + "Function")
        notes.append("function \(qualified) is named \(name): _PostgrestRpc already has \(bare)")
      }
      func signature(_ name: String) -> String {
        let labels = plan.parameters.map { "\(Naming.unescaped($0.label ?? "_")):" }.joined()
        let types = plan.parameters.map { "\($0.type.syntax)" }.joined(separator: ",")
        return "\(Naming.unescaped(name))(\(labels)) \(types)"
      }
      if !taken.insert(signature(name)).inserted {
        let base = name
        name =
          (2...).lazy.map { Naming.identifier("\(Naming.unescaped(base))\($0)") }
          .first { taken.insert(signature($0)).inserted } ?? base
        notes.append(
          "function \(qualified) is named \(name): another call is also named "
            + signature(base).prefix { $0 != " " })
      }
      functions[index].name = name
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
    let names = numberRepeats(
      in: bases, avoiding: taken, kind: "member",
      labels: members.map { "function \($0.function.name.schema).\($0.function.name.name)" })
    return zip(members, names).map {
      ComputedPlan(name: $1, function: $0.function.name.name, kind: $0.kind)
    }
  }

  /// `bases`, with every repeat after the first numbered past the names in `taken`, and noted.
  /// `labels` names each one in the note.
  private mutating func numberRepeats(
    in bases: [String],
    avoiding taken: Set<String>,
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
    let names = numberRepeats(
      in: bases, avoiding: [], kind: "value", labels: type.values.map { "\(label) \($0)" })
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
    let names = numberRepeats(
      in: bases, avoiding: [], kind: "column",
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
    case .materializedView, .foreignTable, .functionResult: true
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

  /// The `pg_catalog` types whose Swift type is in `Foundation`.
  fileprivate static let foundationScalarTypes = [
    "uuid": "UUID",
    "numeric": "Decimal",
    "timestamptz": "Date", "timestamp": "Date", "date": "Date",
  ]

  /// One Swift type per Postgres type. A type with no plain Swift counterpart gets one of
  /// PostgREST's `_Postgres…` types when that changes what compiles or how a value is encoded: a
  /// range gets the range filters, an `interval` or a `time` gets no `like`, a `bytea` is read in
  /// hex. `JSONValue` is only ever `json`/`jsonb`, so it can stand for a JSON column.
  private static let scalarTypes: [String: SwiftType] =
    foundationScalarTypes
    .mapValues(SwiftType.named)
    .merging(
      [
        "text": .named("String"), "varchar": .named("String"), "bpchar": .named("String"),
        "char": .named("String"),
        "inet": .named("String"), "cidr": .named("String"), "macaddr": .named("String"),
        "money": .named("String"), "xml": .named("String"),
        "bool": .named("Bool"),
        "int2": .named("Int"), "int4": .named("Int"), "int8": .named("Int"),
        "float4": .named("Double"), "float8": .named("Double"),
        "json": .named("JSONValue"), "jsonb": .named("JSONValue"),
        "int4range": .generic("_PostgresRange", .named("Int")),
        "int8range": .generic("_PostgresRange", .named("Int")),
        "numrange": .generic("_PostgresRange", .named("Decimal")),
        "tsrange": .generic("_PostgresRange", .named("Date")),
        "tstzrange": .generic("_PostgresRange", .named("Date")),
        "daterange": .generic("_PostgresRange", .named("Date")),
        "interval": .named("_PostgresInterval"),
        "time": .named("_PostgresTime"), "timetz": .named("_PostgresTime"),
        "bytea": .named("_PostgresBytes"),
      ],
      uniquingKeysWith: { first, _ in first })

  /// A type with no mapping, such as a composite or a geometric type, is `_PostgresUnmapped`, with
  /// a note: it decodes whatever PostgREST sends for the column and writes it back unchanged, so
  /// generation never stops at one column. A computed field's return type follows the same rule.
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
    let arrayElementName = arrayElement(of: name)
    let element = arrayElementName ?? name
    let scalar: SwiftType
    if let enumTypeName = enumID.flatMap({ enumTypeNames[$0] }) {
      scalar = .named(enumTypeName)
    } else if let mapped = schema == "pg_catalog" ? Self.scalarTypes[element] : nil {
      scalar = mapped
    } else if element == "citext" {
      // An extension type, so its schema is wherever the extension was installed.
      scalar = .named("String")
    } else {
      scalar = .named("_PostgresUnmapped")
      notes.append(
        "\(subject) \(schema).\(element), which is not mapped; it is decoded as _PostgresUnmapped")
    }
    return arrayElementName == nil ? scalar : .array(scalar)
  }
}

extension FilePlan {
  /// The generated file: one `enum` per enum type and one `@Table` struct per relation,
  /// formatted, ending in one newline.
  func render(accessControl: Options.AccessControl) throws -> String {
    let access: DeclModifierListSyntax =
      accessControl == .public ? [DeclModifierSyntax(name: .keyword(.public))] : []
    let usesFoundation =
      (relations + functionResults).contains { relation in
        relation.properties.contains { $0.type.usesFoundation }
          || relation.computed.contains {
            if case .field(let type) = $0.kind { type.usesFoundation } else { false }
          }
      }
      || functions.contains { function in
        function.parameters.contains { $0.type.usesFoundation }
          || { if case .value(let type) = function.result { type.usesFoundation } else { false } }()
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
          "\(access) enum \(TokenSyntax.identifier(schema.typeName)): _PostgrestSchema"
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

      for relation in relations + functionResults {
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
              let (wrapper, value): (String, SwiftType) =
                switch member.kind {
                case .field(let valueType): ("_PostgrestComputedField", valueType)
                case .toOne(let target): ("_PostgrestToOneRelation", .named(target))
                case .toMany(let target): ("_PostgrestToManyRelation", .named(target))
                }
              DeclSyntax(
                """
                \(access) var \(name): \(raw: wrapper)<\(type), \(value.syntax)> \
                { .init(\(literal)) }
                """
              )
            }
          }
          .with(\.leadingTrivia, .newlines(2))
        }
      }

      if !functions.isEmpty {
        try ExtensionDeclSyntax("extension _PostgrestRpc") {
          for (index, function) in functions.enumerated() {
            MemberBlockItemSyntax(
              leadingTrivia: index == 0 ? .newline : .newlines(2),
              decl: functionDecl(function, access: access))
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

  /// A method that calls the function through the `_PostgrestRpc` entry point its result needs.
  private func functionDecl(_ function: FunctionPlan, access: DeclModifierListSyntax) -> DeclSyntax
  {
    let parameters = function.parameters.map { parameter in
      let names =
        switch (parameter.label, parameter.internalName) {
        case (nil, _): "_ body"
        case (let label?, let internalName?): "\(label) \(internalName)"
        case (let label?, nil): label
        }
      return "\(names): \(parameter.type.syntax)\(parameter.hasDefault ? " = nil" : "")"
    }.joined(separator: ", ")

    let (entryPoint, returnType): (String, String) =
      switch function.result {
      case .rows(let row): ("rows", "_PostgrestQuery<\(row), [\(row)]>")
      case .row(let row): ("row", "_PostgrestFunctionCall<\(row)?>")
      case .value(let type): ("value", "_PostgrestFunctionCall<\(type.syntax)>")
      case .nothing: ("perform", "_PostgrestFunctionCall<Void>")
      }

    var arguments = [StringLiteralExprSyntax(content: function.function).description]
    if function.parameters.count == 1, function.parameters[0].label == nil {
      arguments.append("arguments: _PostgrestArguments(body)")
    } else if !function.parameters.isEmpty {
      let entries = function.parameters.map {
        "\(StringLiteralExprSyntax(content: $0.argument)): \($0.variable)"
      }
      arguments.append("arguments: [\(entries.joined(separator: ", "))]")
    }
    if let schema = function.schemaTypeName {
      arguments.append("schema: \(schema).self")
    }

    return DeclSyntax(
      """
      \(access) func \(raw: function.name)(\(raw: parameters)) throws -> \(raw: returnType) {
        try self.\(raw: entryPoint)(\(raw: arguments.joined(separator: ", ")))
      }
      """
    )
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
