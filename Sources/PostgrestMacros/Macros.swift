//
//  Macros.swift
//  PostgrestMacros
//
//  Created by Guilherme Souza on 21/08/26.
//

// Re-exported so a single `import PostgrestMacros` is enough: the macros synthesize conformances to
// protocols that live in `PostgREST`, and a user should not have to import both.
@_exported public import PostgREST

/// Synthesizes ``PostgrestRelation`` conformance for a struct that maps to a relation.
///
/// ```swift
/// @Table("todos")
/// struct Todo {
///   @PrimaryKey var id: Int
///   var task: String
///   @Default var isDone: Bool
///   @Column("due_at") var dueDate: Date?
/// }
/// ```
///
/// Property names convert camelCase to snake_case; ``Column(_:)`` overrides a single name. The
/// generated `CodingKeys` and the generated column mapping come from the same input, so an insert
/// body and a filter can never disagree about a column.
///
/// The annotated type must be declared at file scope. The macro attaches an extension, and Swift
/// does not allow an extension of a type nested inside another type.
///
/// - Parameters:
///   - name: The relation's name as PostgREST addresses it.
///   - schema: The Postgres schema. Defaults to `"public"`.
///   - readOnly: Pass `true` for a view. The type then conforms to ``PostgREST/PostgrestRelation``
///     only, and the write methods are not available on it.
@attached(
  extension,
  conformances: Decodable, Sendable, PostgrestRelation, PostgrestWritableRelation,
  names: named(relationName), named(schema), named(selectString), named(columnName(for:)),
  named(CodingKeys), named(Insert), named(Update)
)
public macro Table(
  _ name: String,
  schema: String = "public",
  readOnly: Bool = false
) = #externalMacro(module: "PostgrestMacrosPlugin", type: "TableMacro")

/// Overrides the database column name for a property.
///
/// Use it for any name the camelCase-to-snake_case convention cannot produce.
///
/// - Parameter name: The column name PostgREST expects.
@attached(peer)
public macro Column(_ name: String) =
  #externalMacro(
    module: "PostgrestMacrosPlugin", type: "MarkerMacro"
  )

/// Marks a property as the relation's primary key, excluding it from the generated `Insert`.
@attached(peer)
public macro PrimaryKey() =
  #externalMacro(
    module: "PostgrestMacrosPlugin", type: "MarkerMacro"
  )

/// Marks a property as having a database default, making it optional in the generated `Insert`.
///
/// Leaving it `nil` omits the column from the request body, so the database fills it in.
@attached(peer)
public macro Default() =
  #externalMacro(
    module: "PostgrestMacrosPlugin", type: "MarkerMacro"
  )

/// Declares a named subset of a relation's columns.
///
/// ```swift
/// @SelectionOf(Todo.self)
/// struct TodoSummary {
///   var id: Int
///   var isDone: Bool
/// }
///
/// let rows = try await client.from(Todo.self).select(TodoSummary.self).execute().value
/// ```
///
/// Property names follow the same snake_case conversion as ``Table(_:schema:readOnly:)``, and
/// ``Column(_:)`` overrides one. The expansion emits references to the relation's own columns, so a
/// property that names no column on it fails to compile.
///
/// The annotated type must be declared at file scope. The macro attaches an extension, and Swift
/// does not allow an extension of a type nested inside another type.
///
/// - Parameter relation: The relation this selects from, for example `Todo.self`.
@attached(
  extension,
  conformances: Decodable, Sendable, PostgrestSelection,
  names: named(Source), named(selectString), named(CodingKeys), named(_columnCheck)
)
public macro SelectionOf(_ relation: Any.Type) =
  #externalMacro(
    module: "PostgrestMacrosPlugin", type: "SelectionOfMacro"
  )
