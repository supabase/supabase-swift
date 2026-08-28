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
//
// Each embedded column implements `_deriving(_:)` to place a derivation inside its parentheses,
// and declares its `Position`. Those two lines are all either kind contributes: `cast(to:)`,
// `jsonText(_:)`, `jsonObject(_:)` and the five aggregates are declared once on
// `PostgrestColumnExpression` and are correct here for free.

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
  public typealias Position = PostgrestSelectAndOrder

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

  public func _deriving<V, P: PostgrestPosition>(
    _ derivation: String
  ) -> PostgrestDerivedExpression<Root, V, P> {
    PostgrestDerivedExpression<Root, V, P>(embed: embed, inner: inner + derivation)
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
  public typealias Position = PostgrestSelectOnly

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

  public func _deriving<V, P: PostgrestPosition>(
    _ derivation: String
  ) -> PostgrestDerivedExpression<Root, V, P> {
    PostgrestDerivedExpression<Root, V, P>(embed: embed, inner: inner + derivation)
  }
}
