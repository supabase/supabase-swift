//
//  Macros.swift
//  PostgrestMacros
//
//  Created by Guilherme Souza on 21/08/26.
//

// Re-exported so a single `import PostgrestMacros` is enough: the macros synthesize conformances to
// protocols that live in `PostgREST`, and a user should not have to import both.
@_exported public import PostgREST

/// Synthesizes ``_PostgrestRelation`` conformance for a struct that maps to a relation.
///
/// ```swift
/// @Table("todos")
/// struct Todo {
///   @PrimaryKey @Default var id: Int
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
/// The macro also generates a `Columns` namespace holding one column value per property, which
/// filter and order closures receive:
///
/// ```swift
/// .where { ($0.isDone.eq(false) && $0.priority.gt(3)) || $0.id.eq(7) }
/// .order { $0.dueDate.desc() }
/// ```
///
/// Each column carries its database name and its Swift type, so an operand of the wrong type is
/// a compile error. Casts, JSON paths and aggregates compose onto a column and stay checked.
///
/// The annotated type must be declared at file scope. The macro attaches an extension, and Swift
/// does not allow an extension of a type nested inside another type.
///
/// > Warning: The typed query API is experimental. Its shape may change in a minor release.
/// > Declaring a `@Table` type needs no opt-in, but a file that queries one through
/// > `from(_:)` needs `@_spi(Experimental) import Supabase`.
///
/// - Parameters:
///   - name: The relation's name as PostgREST addresses it.
///   - schema: The type naming the Postgres schema, written as `PrivateSchema.self`. Defaults to
///     ``PostgREST/_PublicSchema``.
///   - readOnly: Pass `true` for a view. The type then conforms to ``PostgREST/_PostgrestRelation``
///     only, and the write methods are not available on it.
@attached(
  extension,
  conformances: Decodable, Sendable, _PostgrestRelation, _PostgrestKeyedRelation,
  _PostgrestWritableRelation,
  names: named(relationName), named(Schema), named(selectString), named(Columns),
  named(columns), named(primaryKeyColumns), named(CodingKeys), named(Draft)
)
public macro Table(
  _ name: String,
  schema: any _PostgrestSchema.Type = _PublicSchema.self,
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

/// Marks a property as part of the relation's primary key.
///
/// This does **not** make the column optional in `Draft`. Being the key says nothing about
/// whether the database can supply the value — a `SERIAL` or identity column can, and a natural
/// key like a country code cannot. Add ``Default()`` for the ones it can:
///
/// ```swift
/// @PrimaryKey @Default var id: Int      // generated — omit it on insert
/// @PrimaryKey var code: String          // natural — required on insert
/// ```
///
/// Apply it to more than one property for a compound key. Each half is then required unless it is
/// also ``Default()``, so an incomplete key is a compile error rather than a request PostgREST
/// rejects. This matches how `postgres-meta` types supabase-js: it makes a column optional from
/// `is_nullable || is_identity || default_value !== null`, and never consults the primary key.
///
/// An update can assign the key like any other column, so a natural key can be renamed:
/// ``PostgREST/_PostgrestUpdate`` takes a key path to any stored property, and the key is not
/// special among them. Which rows a write touches is decided by the filters on the mutation, not
/// by this marker.
///
/// What the marker does produce is a ``PostgREST/_PostgrestKeyedRelation`` conformance, carrying
/// ``PostgREST/_PostgrestKeyedRelation/primaryKeyColumns`` — the column names in declaration order.
/// That conformance is what makes `upsert(_:)` available: it derives the conflict target from the
/// key, so no caller repeats it as a string. Leave the marker off and the relation does not conform,
/// which turns an upsert with no target into a compile error rather than a silent plain insert.
/// With `@Default` as well, the key is optional in `Draft`, and an upsert that omits it inserts by
/// design: omit the key to insert, supply it to merge.
@attached(peer)
public macro PrimaryKey() =
  #externalMacro(
    module: "PostgrestMacrosPlugin", type: "MarkerMacro"
  )

/// Marks a property as having a database default, making it optional in the generated `Draft`.
///
/// Leaving it `nil` omits the column from the request body, so the database fills it in. This is
/// the only marker that makes a column optional — including for a primary key, which needs
/// `@PrimaryKey @Default` when the database generates it.
@attached(peer)
public macro Default() =
  #externalMacro(
    module: "PostgrestMacrosPlugin", type: "MarkerMacro"
  )

/// Marks a property as a column the database fills in and refuses to be written: `GENERATED
/// ALWAYS AS IDENTITY`, or `GENERATED ALWAYS AS (…) STORED`.
///
/// The property stays in the decoded row, in `CodingKeys` and in `Columns`, so it selects,
/// filters and orders like any other column. It is left out of `Draft`, and its column is a
/// ``PostgREST/_PostgrestGeneratedColumn``, which ``PostgREST/_PostgrestUpdate`` cannot assign. A
/// write naming it would be rejected by Postgres with `428C9`; with the marker it does not compile.
///
/// ```swift
/// @PrimaryKey @Generated var id: Int   // in the row and in filters, absent from Draft and Update
/// ```
///
/// Compare ``Default()``, which keeps the column writable and only makes it optional in `Draft`:
/// a `SERIAL` or `GENERATED BY DEFAULT` column accepts a value, an `ALWAYS` one does not. The
/// marker is what a schema generator emits for `identity_generation == 'ALWAYS'`, the field
/// `postgres-meta` reads to type the same column `?: never` for supabase-js.
@attached(peer)
public macro Generated() =
  #externalMacro(
    module: "PostgrestMacrosPlugin", type: "MarkerMacro"
  )

/// Declares a property as an embedded relation, identified by its foreign key column.
///
/// ```swift
/// @SelectionOf(Todo.self)
/// struct TodoWithComments {
///   var id: UUID
///   var task: String
///   @Relationship(\Comment.todoID) var comments: [CommentBody]
/// }
///
/// // "id:id,task:task,comments:comments!todo_id(id:id,body:body)"
/// ```
///
/// The foreign key is itself a column, so the key path exists whichever side declares it:
/// `\Comment.todoID` for the one-to-many above, and `\Message.senderID` for the many-to-one
/// `@Relationship(\Message.senderID) var sender: UserName?`. Either way it is compiler-checked, and
/// it needs nothing from the schema generator that a column does not already provide.
///
/// Naming it is a correctness feature, not only compile-time sugar. PostgREST answers an ambiguous
/// embed — two foreign keys joining the same pair of relations — with HTTP 300 `PGRST201`. Because
/// the key path is required, the generated `select` always carries the `!todo_id` hint, so that
/// response cannot be produced.
///
/// The embed's shape comes from the property's own type, with `Array` and `Optional` layers
/// removed: `[CommentBody]` and `UserName?` both embed the selection, one as many rows and one as
/// at most one. That selection names its own relation, which is what the embed is addressed by.
///
/// Embeds belong to a selection. Writing this on a ``Table(_:schema:readOnly:)`` property is a
/// compile error.
///
/// - Parameter foreignKey: A key path to the foreign key column, for example `\Comment.todoID`.
@attached(peer)
public macro Relationship(_ foreignKey: AnyKeyPath) =
  #externalMacro(
    module: "PostgrestMacrosPlugin", type: "MarkerMacro"
  )

/// Declares a property as an embed through a computed relationship: a function whose only
/// argument is the selection's relation row type, returning a row or a set of rows of another
/// relation.
///
/// ```swift
/// extension Channel.Columns {
///   var getMessages: _PostgrestToManyRelation<Channel, Message> { .init("get_messages") }
/// }
///
/// @SelectionOf(Channel.self)
/// struct ChannelFeed {
///   var slug: String
///   @Relationship(computed: \Channel.Columns.getMessages) var messages: [Message]
/// }
///
/// // "slug:slug,messages:get_messages(*)"
/// ```
///
/// The key path names the relationship on the selection's relation's `Columns` namespace, where a
/// ``PostgREST/_PostgrestToManyRelation`` or ``PostgREST/_PostgrestToOneRelation`` declares it. The
/// relationship's target has to be the property's selection's relation, or the expansion does not
/// compile. PostgREST addresses the embed by the function name, with no foreign-key hint: a
/// function name is never ambiguous.
///
/// Scopes work as for a foreign-key embed: ``PostgREST/_PostgrestQuery/embedded(_:_:)`` and
/// ``PostgREST/_PostgrestQuery/requiring(_:_:)``.
///
/// - Parameter computed: A key path to the relationship on the relation's `Columns`, for example
///   `\Channel.Columns.getMessages`.
@attached(peer)
public macro Relationship(computed: AnyKeyPath) =
  #externalMacro(
    module: "PostgrestMacrosPlugin", type: "MarkerMacro"
  )

/// Declares a selection property as an aggregate of one of the relation's columns.
///
/// ```swift
/// @SelectionOf(Order.self)
/// struct OrderTotals {
///   var category: String
///   @Aggregate(.sum, of: \Order.amount) var total: Double?
///   @Aggregate(.sum, of: \Order.tax) var taxTotal: Double?
///   @Aggregate(.count) var rows: Int
/// }
///
/// // "category:category,total:amount.sum(),tax_total:tax.sum(),rows:count()"
/// ```
///
/// Each entry is aliased with the property name, so two aggregates of the same function come back
/// under their own keys rather than both as `sum`. Selecting a plain column alongside groups by it.
///
/// The key path names the relation's stored property, written with its root. The expansion checks
/// it against the selection's relation, and checks the property's type against the aggregate's
/// result: `Double` for `sum` and `avg`, `Int` for `count`, and the column's own type for `min`
/// and `max`. Declare `sum`, `avg`, `min` and `max` optional — they are `null` when no rows match.
///
/// With no column, `.count` counts rows: `count()`. Every other function requires one.
///
/// For an expression this attribute does not cover — a cast, a JSON path, an aggregate through an
/// embed, or a `sum` decoded as `Int` or `Decimal` past 2^53 — declare it on the relation's
/// `Columns` and select it under a property of the same name.
///
/// Aggregates belong to a selection. Writing this on a ``Table(_:schema:readOnly:)`` property is a
/// compile error.
///
/// > Important: Requires PostgREST's `db-aggregates-enabled` setting. It is on for hosted
/// > Supabase and off by default when self-hosting.
///
/// - Parameters:
///   - function: The aggregate function, for example `.sum`.
///   - column: A key path to the column, for example `\Order.amount`. Omit it only for `.count`.
@attached(peer)
public macro Aggregate(_ function: _PostgrestAggregateFunction, of column: AnyKeyPath? = nil) =
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
/// A property that holds another selection rather than a column is an embed, declared with
/// ``Relationship(_:)``. A selection with at least one embed also gets an `Embeds` namespace and
/// conforms to ``PostgREST/_PostgrestEmbeddingSelection``, which is what makes
/// ``PostgREST/_PostgrestQuery/embedded(_:_:)`` and ``PostgREST/_PostgrestQuery/requiring(_:_:)``
/// available on a query selecting it.
///
/// A property that holds an aggregate is declared with ``Aggregate(_:of:)``. A property can also
/// name a member you declare on the relation's `Columns`, such as a cast. Either way, the entry
/// is aliased with the property name like any other:
///
/// ```swift
/// extension Order.Columns {
///   var amountText: _PostgrestCastColumn<Order, String> { amount.cast(to: .text) }
/// }
///
/// @SelectionOf(Order.self)
/// struct OrderTotals {
///   var category: String
///   @Aggregate(.sum, of: \Order.amount) var total: Double?
///   var amountText: String
/// }
///
/// // "category:category,total:amount.sum(),amount_text:amount::text"
/// ```
///
/// The annotated type must be declared at file scope. The macro attaches an extension, and Swift
/// does not allow an extension of a type nested inside another type.
///
/// - Parameter relation: The relation this selects from, for example `Todo.self`.
@attached(
  extension,
  conformances: Decodable, Sendable, _PostgrestSelection, _PostgrestEmbeddingSelection,
  names: named(Source), named(selectString), named(CodingKeys), named(_columnCheck),
  named(Embeds), named(embeds)
)
public macro SelectionOf(_ relation: Any.Type) =
  #externalMacro(
    module: "PostgrestMacrosPlugin", type: "SelectionOfMacro"
  )
