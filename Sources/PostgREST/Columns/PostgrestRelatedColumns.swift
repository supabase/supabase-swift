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
/// Projections of a to-one embed are orderable, unlike ``_PostgrestToManyRelation``'s.
@dynamicMemberLookup
public struct _PostgrestToOneRelation<
  Root: _PostgrestRelation,
  Target: _PostgrestRelation
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
  public subscript<C: _PostgrestColumnExpression>(
    dynamicMember keyPath: KeyPath<Target.Columns, C>
  ) -> _PostgrestToOneColumn<Root, Target, C.Value> where C.Root == Target {
    _PostgrestToOneColumn(
      embed: postgrestEmbedName,
      inner: Target.columns[keyPath: keyPath].postgrestExpression
    )
  }
}

/// A to-**many** embedded relation (one-to-many or many-to-many), reached from its parent's
/// column namespace. Declared once by the generator, as ``_PostgrestToOneRelation`` is.
///
/// Its projections are select position only: PostgREST answers `order=children(amount).desc` with
/// `PGRST118` ("do not form a many-to-one or one-to-one relationship").
@dynamicMemberLookup
public struct _PostgrestToManyRelation<
  Root: _PostgrestRelation,
  Target: _PostgrestRelation
>: Sendable {
  /// The name PostgREST addresses the embed by, including any disambiguating foreign-key hint.
  ///
  /// Prefixed for the same reason as ``_PostgrestToOneRelation/postgrestEmbedName``.
  public let postgrestEmbedName: String

  /// - Parameter name: The embed name.
  public init(_ name: String) {
    self.postgrestEmbedName = name
  }

  /// Projects a column of the embedded relation into the parent's frame.
  public subscript<C: _PostgrestColumnExpression>(
    dynamicMember keyPath: KeyPath<Target.Columns, C>
  ) -> _PostgrestToManyColumn<Root, Target, C.Value> where C.Root == Target {
    _PostgrestToManyColumn(
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
// `_PostgrestColumnExpression` and are correct here for free.

/// A column of a to-**one** embedded relation, seen from the parent.
///
/// Selectable and orderable, not filterable: an embedded column renders `parent(title)` in a
/// `select` list but `parent.title` on the left of a filter, and the filter form also needs an
/// `!inner` decision. Filtering inside an embed is a scope on the query instead —
/// ``_PostgrestQuery/embedded(_:_:)`` and ``_PostgrestQuery/requiring(_:_:)`` — which makes that
/// decision explicit at the call site.
public struct _PostgrestToOneColumn<
  Root: _PostgrestRelation,
  Target: _PostgrestRelation,
  Value
>: _PostgrestColumnExpression, _PostgrestOrderableExpression {
  public typealias Position = _PostgrestSelectAndOrder

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

  public func _deriving<V, P: _PostgrestPosition>(
    _ derivation: String
  ) -> _PostgrestDerivedExpression<Root, V, P> {
    _PostgrestDerivedExpression<Root, V, P>(embed: embed, inner: inner + derivation)
  }
}

/// A column of a to-**many** embedded relation, seen from the parent.
///
/// Select position only — `order=children(amount).desc` is `PGRST118` — and an embedded filter is
/// scoped on the query (``_PostgrestQuery/embedded(_:_:)``) rather than written inline.
public struct _PostgrestToManyColumn<
  Root: _PostgrestRelation,
  Target: _PostgrestRelation,
  Value
>: _PostgrestColumnExpression {
  public typealias Position = _PostgrestSelectOnly

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

  public func _deriving<V, P: _PostgrestPosition>(
    _ derivation: String
  ) -> _PostgrestDerivedExpression<Root, V, P> {
    _PostgrestDerivedExpression<Root, V, P>(embed: embed, inner: inner + derivation)
  }
}
