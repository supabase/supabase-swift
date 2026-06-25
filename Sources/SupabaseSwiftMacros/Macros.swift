/// Marks a struct as a PostgREST table.
///
/// Synthesizes:
/// - `TableRepresentable` or `ReadOnlyTableRepresentable` conformance
/// - `static let tableName`, `schema`, `selectString = "*"`
/// - `static func columnName<V>(for:) -> String`
/// - Nested `Insert` struct (excluded when readOnly: true)
/// - Nested `Update` struct (excluded when readOnly: true)
/// - `CodingKeys` enum with snake_case mapping
///
/// - Parameters:
///   - tableName: The PostgREST table or view name.
///   - schema: The PostgreSQL schema (default: "public").
///   - readOnly: Pass true for views — omits Insert/Update and conforms to ReadOnlyTableRepresentable.
@attached(
  member, names: named(Insert), named(Update), named(CodingKeys),
  named(columnName))
@attached(
  extension,
  conformances: TableRepresentable, ReadOnlyTableRepresentable,
  SelectionRepresentable,
  names: named(tableName), named(schema), named(selectString))
public macro Table(
  _ tableName: String,
  schema: String = "public",
  readOnly: Bool = false
) = #externalMacro(module: "SupabaseMacros", type: "TableMacro")

/// Marks a struct as a partial column projection of table T.
///
/// Synthesizes:
/// - `SelectionRepresentable` conformance
/// - `static var selectString: String` — computed from field names, resolved at runtime
///   for nested SelectionRepresentable fields (e.g. `"id,title,profile(\(Profile.selectString))"`)
/// - `CodingKeys` enum with snake_case mapping
///
/// Field names must match column or relationship names on T. Type mismatches are caught
/// at decode time via Decodable. Compile-time cross-type validation is a future enhancement.
///
/// - Parameter table: The parent TableRepresentable type, e.g. `Todo.self`.
@attached(member, names: named(CodingKeys))
@attached(
  extension, conformances: SelectionRepresentable, names: named(selectString))
public macro SelectionOf(_ table: Any.Type) =
  #externalMacro(
    module: "SupabaseMacros", type: "SelectionOfMacro")

/// Marks a stored property as the table primary key.
/// Excluded from the synthesized Insert and Update types.
@attached(peer)
public macro PrimaryKey() =
  #externalMacro(
    module: "SupabaseMacros", type: "PrimaryKeyMacro")

/// Marks a stored property as having a database-side default value.
/// The property becomes Optional with `= nil` in the synthesized Insert type.
@attached(peer)
public macro Default() =
  #externalMacro(
    module: "SupabaseMacros", type: "DefaultMacro")

/// Overrides the snake_case-derived column name for a stored property.
/// - Parameter name: The exact PostgREST column name.
@attached(peer)
public macro Column(_ name: String) =
  #externalMacro(
    module: "SupabaseMacros", type: "ColumnMacro")

/// Declares a foreign-key relationship. Excluded from Insert and Update.
/// In @SelectionOf structs, a field typed as the referenced table or a @SelectionOf of it
/// produces an embedded PostgREST select (e.g. `"profile(*)"` or `"profile(id,name)"`).
/// - Parameters:
///   - foreignKey: The FK column name on this table (e.g. `"user_id"`).
///   - references: The referenced TableRepresentable type (e.g. `Profile.self`).
@attached(peer)
public macro Relationship(_ foreignKey: String, references: Any.Type) =
  #externalMacro(module: "SupabaseMacros", type: "RelationshipMacro")
