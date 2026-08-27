//
//  PostgrestRelatedColumns.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

// MARK: - Relations

/// A to-**one** embedded relation (many-to-one or one-to-one), reached from its parent's column
/// namespace.
///
/// Projecting a column through it gives one checked chain:
///
/// ```swift
/// Order.columns.todo.title   // todo(title)
/// ```
///
/// The relationship is declared once, here on the namespace, by the generator that has the
/// foreign key from `postgres-meta`. `@Table` cannot emit one: a macro sees syntax only.
///
/// Projections of a to-one embed are orderable, unlike ``PostgrestToManyRelation``'s.
@dynamicMemberLookup
public struct PostgrestToOneRelation<
  Root: PostgrestRelation,
  Target: PostgrestRelation
>: Sendable {
  /// The name PostgREST addresses the embed by, including any disambiguating foreign-key hint.
  ///
  /// Prefixed because every public member of this type shadows a projected column of the same
  /// name: `@dynamicMemberLookup` only fires when no real member matches, so a plain `name` here
  /// would make `orders.name` return this string instead of the embedded `name` column.
  public let postgrestEmbedName: String

  /// - Parameter name: The embed name.
  public init(_ name: String) {
    self.postgrestEmbedName = name
  }

  /// Projects a column of the embedded relation into the parent's frame.
  ///
  /// The result is rooted on `Root`, so it belongs in the parent's `select` list, while its
  /// `Value` still comes from `Target`.
  public subscript<C: PostgrestColumnExpression>(
    dynamicMember keyPath: KeyPath<Target.Columns, C>
  ) -> PostgrestToOneColumn<Root, Target, C.Value> where C.Root == Target {
    PostgrestToOneColumn(
      embed: postgrestEmbedName,
      inner: Target.columns[keyPath: keyPath].postgrestExpression
    )
  }
}

/// A to-**many** embedded relation (one-to-many or many-to-many), reached from its parent's
/// column namespace. Declared once by the generator, as ``PostgrestToOneRelation`` is.
///
/// Its projections are select position only: PostgREST answers `order=children(amount).desc` with
/// `PGRST118` ("do not form a many-to-one or one-to-one relationship").
@dynamicMemberLookup
public struct PostgrestToManyRelation<
  Root: PostgrestRelation,
  Target: PostgrestRelation
>: Sendable {
  /// The name PostgREST addresses the embed by, including any disambiguating foreign-key hint.
  ///
  /// Prefixed for the same reason as ``PostgrestToOneRelation/postgrestEmbedName``.
  public let postgrestEmbedName: String

  /// - Parameter name: The embed name.
  public init(_ name: String) {
    self.postgrestEmbedName = name
  }

  /// Projects a column of the embedded relation into the parent's frame.
  public subscript<C: PostgrestColumnExpression>(
    dynamicMember keyPath: KeyPath<Target.Columns, C>
  ) -> PostgrestToManyColumn<Root, Target, C.Value> where C.Root == Target {
    PostgrestToManyColumn(
      embed: postgrestEmbedName,
      inner: Target.columns[keyPath: keyPath].postgrestExpression
    )
  }
}

// MARK: - Columns

/// A column of a to-**one** embedded relation, seen from the parent.
///
/// Selectable and orderable, not filterable: an embedded column renders `parent(title)` in a
/// `select` list but `parent.title` on the left of a filter, and the filter form also needs an
/// `!inner` decision. Filtering inside an embed is scoped separately (SDK-1575), and reads
/// ``embeddedFilterName``.
public struct PostgrestToOneColumn<
  Root: PostgrestRelation,
  Target: PostgrestRelation,
  Value
>: PostgrestColumnExpression, PostgrestOrderableExpression {
  let embed: String
  let inner: String

  /// The `select`-list form, `parent(title)`. Also the form `order` accepts for a to-one embed.
  public var postgrestExpression: String { "\(embed)(\(inner))" }

  /// The filter form, `parent.title`.
  public var embeddedFilterName: String { "\(embed).\(inner)" }

  init(embed: String, inner: String) {
    self.embed = embed
    self.inner = inner
  }
}

/// A column of a to-**many** embedded relation, seen from the parent.
///
/// Select position only — `order=children(amount).desc` is `PGRST118` — and an embedded filter is
/// scoped rather than written inline (SDK-1575).
public struct PostgrestToManyColumn<
  Root: PostgrestRelation,
  Target: PostgrestRelation,
  Value
>: PostgrestColumnExpression {
  let embed: String
  let inner: String

  /// The `select`-list form, `children(amount)`.
  public var postgrestExpression: String { "\(embed)(\(inner))" }

  /// The filter form, `children.amount`.
  public var embeddedFilterName: String { "\(embed).\(inner)" }

  init(embed: String, inner: String) {
    self.embed = embed
    self.inner = inner
  }
}

/// A cast, JSON path or aggregate applied to a to-**one** embedded column — **select position
/// only**.
///
/// A to-one projection is orderable but a cast or an aggregate of one is not, so those methods
/// return this type instead of `Self`. It keeps `embed` and `inner` apart, so anything chained
/// onward also lands inside the embed's parentheses:
/// `Order.columns.todo.amount.sum().cast(to: .text)` renders `todo(amount.sum()::text)`, with the
/// cast applied — the flattened form `todo(amount.sum())::text` returns the value uncast.
///
/// > Note: Landing inside the parentheses makes an invalid chain loud rather than silent.
/// > PostgREST accepts only `::` after an aggregate, so a second aggregate or a JSON path is a
/// > 400. The to-many side behaves the same way.
///
/// > Important: When the operation is an aggregate, everything ``PostgrestAggregate`` documents
/// > still applies — the `db-aggregates-enabled` requirement, and the response being an array of
/// > objects keyed by the function name.
public struct PostgrestToOneDerivedColumn<
  Root: PostgrestRelation,
  Target: PostgrestRelation,
  Value
>: PostgrestColumnExpression {
  let embed: String
  let inner: String

  /// The `select`-list form, `parent(title::text)`. There is no `order` or filter form.
  public var postgrestExpression: String { "\(embed)(\(inner))" }

  init(embed: String, inner: String) {
    self.embed = embed
    self.inner = inner
  }
}

// Every embedded column type shadows the eight accessors it would otherwise inherit from
// `PostgrestColumnExpression`. The inherited versions render *outside* the embed's parentheses —
// `parent(title)::text` rather than `parent(title::text)` — and PostgREST does not reject that:
// it answers 200 and silently drops whatever sits outside. The shadows put the operation inside.

// MARK: - Shadowed accessors (to-one derived)

extension PostgrestToOneDerivedColumn {
  /// Casts this derived projection to another Postgres type.
  ///
  /// > Note: Make a cast the last step. PostgREST applies only the first cast in
  /// > `parent(id::text::int)`, returning a JSON string while the Swift type says `Int`.
  ///
  /// - Returns: A derived projection rendering `embed(inner::sqlType)`.
  public func cast<T>(
    to target: PostgrestCastTarget<T>
  ) -> PostgrestToOneDerivedColumn<Root, Target, T> {
    PostgrestToOneDerivedColumn<Root, Target, T>(
      embed: embed, inner: "\(inner)::\(target.sqlType)")
  }

  /// Reads a `json`/`jsonb` path on this derived projection as text, with `->>`.
  public func jsonText(_ path: String) -> PostgrestToOneDerivedColumn<Root, Target, String> {
    PostgrestToOneDerivedColumn<Root, Target, String>(embed: embed, inner: "\(inner)->>\(path)")
  }

  /// Reads a `json`/`jsonb` path on this derived projection as JSON, with `->`.
  public func jsonObject(_ path: String) -> PostgrestToOneDerivedColumn<Root, Target, Value> {
    PostgrestToOneDerivedColumn(embed: embed, inner: "\(inner)->\(path)")
  }

  /// The sum of this derived projection.
  public func sum() -> PostgrestToOneDerivedColumn<Root, Target, Double> {
    PostgrestToOneDerivedColumn<Root, Target, Double>(embed: embed, inner: "\(inner).sum()")
  }

  /// The mean of this derived projection.
  public func avg() -> PostgrestToOneDerivedColumn<Root, Target, Double> {
    PostgrestToOneDerivedColumn<Root, Target, Double>(embed: embed, inner: "\(inner).avg()")
  }

  /// The smallest value of this derived projection.
  public func min() -> PostgrestToOneDerivedColumn<Root, Target, Value> {
    PostgrestToOneDerivedColumn(embed: embed, inner: "\(inner).min()")
  }

  /// The largest value of this derived projection.
  public func max() -> PostgrestToOneDerivedColumn<Root, Target, Value> {
    PostgrestToOneDerivedColumn(embed: embed, inner: "\(inner).max()")
  }

  /// How many non-null values of this derived projection there are.
  public func count() -> PostgrestToOneDerivedColumn<Root, Target, Int> {
    PostgrestToOneDerivedColumn<Root, Target, Int>(embed: embed, inner: "\(inner).count()")
  }
}

// MARK: - Shadowed accessors (to-one)

extension PostgrestToOneColumn {
  /// Casts this projection to another Postgres type.
  ///
  /// Returns ``PostgrestToOneDerivedColumn``, not `Self`: a to-one projection is orderable and a
  /// cast of one is not.
  ///
  /// - Returns: A select-only derived projection rendering `embed(inner::sqlType)`.
  public func cast<T>(
    to target: PostgrestCastTarget<T>
  ) -> PostgrestToOneDerivedColumn<Root, Target, T> {
    PostgrestToOneDerivedColumn<Root, Target, T>(
      embed: embed, inner: "\(inner)::\(target.sqlType)")
  }

  /// Reads a `json`/`jsonb` path on this projection as text, with `->>`.
  ///
  /// Keeps this type, unlike ``cast(to:)``: an arrow path inside an embed is still orderable.
  public func jsonText(_ path: String) -> PostgrestToOneColumn<Root, Target, String> {
    PostgrestToOneColumn<Root, Target, String>(embed: embed, inner: "\(inner)->>\(path)")
  }

  /// Reads a `json`/`jsonb` path on this projection as JSON, with `->`.
  public func jsonObject(_ path: String) -> PostgrestToOneColumn<Root, Target, Value> {
    PostgrestToOneColumn(embed: embed, inner: "\(inner)->\(path)")
  }

  /// The sum of this projection, over the single related row.
  ///
  /// Returns ``PostgrestToOneDerivedColumn``, not `Self`: a to-one projection is orderable and an
  /// aggregate of one is not.
  public func sum() -> PostgrestToOneDerivedColumn<Root, Target, Double> {
    PostgrestToOneDerivedColumn<Root, Target, Double>(embed: embed, inner: "\(inner).sum()")
  }

  /// The mean of this projection, over the single related row.
  public func avg() -> PostgrestToOneDerivedColumn<Root, Target, Double> {
    PostgrestToOneDerivedColumn<Root, Target, Double>(embed: embed, inner: "\(inner).avg()")
  }

  /// The smallest value of this projection, over the single related row.
  public func min() -> PostgrestToOneDerivedColumn<Root, Target, Value> {
    PostgrestToOneDerivedColumn(embed: embed, inner: "\(inner).min()")
  }

  /// The largest value of this projection, over the single related row.
  public func max() -> PostgrestToOneDerivedColumn<Root, Target, Value> {
    PostgrestToOneDerivedColumn(embed: embed, inner: "\(inner).max()")
  }

  /// How many non-null values of this projection are in the single related row.
  public func count() -> PostgrestToOneDerivedColumn<Root, Target, Int> {
    PostgrestToOneDerivedColumn<Root, Target, Int>(embed: embed, inner: "\(inner).count()")
  }
}

// MARK: - Shadowed accessors (to-many)

extension PostgrestToManyColumn {
  /// Casts this projection to another Postgres type, rendering `children(amount::text)`.
  public func cast<T>(to target: PostgrestCastTarget<T>) -> PostgrestToManyColumn<Root, Target, T> {
    PostgrestToManyColumn<Root, Target, T>(embed: embed, inner: "\(inner)::\(target.sqlType)")
  }

  /// Reads a `json`/`jsonb` path on this projection as text, with `->>`.
  public func jsonText(_ path: String) -> PostgrestToManyColumn<Root, Target, String> {
    PostgrestToManyColumn<Root, Target, String>(embed: embed, inner: "\(inner)->>\(path)")
  }

  /// Reads a `json`/`jsonb` path on this projection as JSON, with `->`.
  public func jsonObject(_ path: String) -> PostgrestToManyColumn<Root, Target, Value> {
    PostgrestToManyColumn(embed: embed, inner: "\(inner)->\(path)")
  }

  /// The sum of this embedded column across the group, rendering `orders(amount.sum())`.
  public func sum() -> PostgrestToManyColumn<Root, Target, Double> {
    PostgrestToManyColumn<Root, Target, Double>(embed: embed, inner: "\(inner).sum()")
  }

  /// The mean of this embedded column across the group.
  public func avg() -> PostgrestToManyColumn<Root, Target, Double> {
    PostgrestToManyColumn<Root, Target, Double>(embed: embed, inner: "\(inner).avg()")
  }

  /// The smallest value of this embedded column in the group.
  public func min() -> PostgrestToManyColumn<Root, Target, Value> {
    PostgrestToManyColumn(embed: embed, inner: "\(inner).min()")
  }

  /// The largest value of this embedded column in the group.
  public func max() -> PostgrestToManyColumn<Root, Target, Value> {
    PostgrestToManyColumn(embed: embed, inner: "\(inner).max()")
  }

  /// How many non-null values of this embedded column are in the group.
  public func count() -> PostgrestToManyColumn<Root, Target, Int> {
    PostgrestToManyColumn<Root, Target, Int>(embed: embed, inner: "\(inner).count()")
  }
}
