// Re-export PostgREST so that code using `@Table`/`@SelectionOf` sees the
// `TableRepresentable`/`SelectionRepresentable` protocols and the typed builders
// without a separate `import PostgREST`.
@_exported public import PostgREST

/// Marks a struct as a PostgREST table.
///
/// Synthesizes:
/// - `static let tableName`, `schema`, `selectString = "*"`
/// - `static func columnName<V>(for:) -> String`
/// - Nested `Insert` struct (excluded when readOnly: true)
/// - Nested `Update` struct (excluded when readOnly: true)
/// - `CodingKeys` enum with snake_case mapping
///
/// **Important:** Due to a Swift compiler limitation, the protocol conformance
/// (`TableRepresentable` or `ReadOnlyTableRepresentable`) must be declared explicitly
/// on the struct — the macro provides the required implementations.
///
/// - Parameters:
///   - tableName: The PostgREST table or view name.
///   - schema: The PostgreSQL schema (default: "public").
///   - readOnly: Pass true for views — omits Insert/Update; conform to ReadOnlyTableRepresentable.
@attached(
  member,
  names: named(CodingKeys), named(tableName), named(schema), named(selectString),
  named(columnName), named(Insert), named(Update))
public macro Table(
  _ tableName: String,
  schema: String = "public",
  readOnly: Bool = false
) = #externalMacro(module: "PostgrestMacrosPlugin", type: "TableMacro")

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
    module: "PostgrestMacrosPlugin", type: "SelectionOfMacro")

/// Marks a stored property as the table primary key.
/// Excluded from the synthesized Insert and Update types.
@attached(peer)
public macro PrimaryKey() =
  #externalMacro(
    module: "PostgrestMacrosPlugin", type: "PrimaryKeyMacro")

/// Marks a stored property as having a database-side default value.
/// The property becomes Optional with `= nil` in the synthesized Insert type.
@attached(peer)
public macro Default() =
  #externalMacro(
    module: "PostgrestMacrosPlugin", type: "DefaultMacro")

/// Overrides the snake_case-derived column name for a stored property.
/// - Parameter name: The exact PostgREST column name.
@attached(peer)
public macro Column(_ name: String) =
  #externalMacro(
    module: "PostgrestMacrosPlugin", type: "ColumnMacro")

/// Declares a foreign-key join in a `@SelectionOf` struct.
/// Not allowed in `@Table` structs — the table row type has no embedded relationships.
///
/// The referenced table type is inferred from the field's type annotation
/// (Optional and Array wrappers are unwrapped automatically).
///
/// - Parameter keyPath: Key path to the FK column on the owning table.
///   Use the explicit root form `\Message.senderId` to identify which table owns the FK.
@attached(peer)
public macro Relationship(_ keyPath: AnyKeyPath) =
  #externalMacro(module: "PostgrestMacrosPlugin", type: "RelationshipMacro")
