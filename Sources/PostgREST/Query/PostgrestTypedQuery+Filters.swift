//
//  PostgrestTypedQuery+Filters.swift
//  PostgREST
//
//  Created by Guilherme Souza on 21/08/26.
//

/// A wrapper that scopes a request by key path.
///
/// ``PostgrestTypedQuery`` conforms, so the key-path filter set is declared once here rather than
/// repeated on every wrapper that needs it. You do not conform your own types to this.
///
/// Only filters live here. `order` and `limit` move the request into
/// ``PostgrestTransformPhase``, so they cannot return `Self` and are declared on
/// ``PostgrestTypedQuery`` instead.
public protocol PostgrestKeyPathFilterable {
  /// The relation whose key paths this wrapper accepts.
  associatedtype Relation: PostgrestRelation

  /// The phase of the underlying request. Filters require a filterable phase.
  associatedtype Phase: PostgrestFilterablePhase

  /// The underlying string-based builder.
  var builder: PostgrestRequestBuilder<Phase> { get }

  /// Wraps a builder, preserving the wrapper's type.
  init(builder: PostgrestRequestBuilder<Phase>)
}

extension PostgrestTypedQuery: PostgrestKeyPathFilterable
where Phase: PostgrestFilterablePhase {
  public typealias Relation = R
}

extension PostgrestKeyPathFilterable {
  /// Matches rows where the column at `column` equals `value`.
  public func eq<V: PostgrestFilterValue>(_ column: KeyPath<Relation, V>, _ value: V) -> Self {
    Self(builder: builder.eq(Relation.columnName(for: column), value: value))
  }

  /// Matches rows where the column at `column` is not equal to `value`.
  public func neq<V: PostgrestFilterValue>(_ column: KeyPath<Relation, V>, _ value: V) -> Self {
    Self(builder: builder.neq(Relation.columnName(for: column), value: value))
  }

  /// Matches rows where the column at `column` is greater than `value`.
  public func gt<V: PostgrestFilterValue>(_ column: KeyPath<Relation, V>, _ value: V) -> Self {
    Self(builder: builder.gt(Relation.columnName(for: column), value: value))
  }

  /// Matches rows where the column at `column` is greater than or equal to `value`.
  public func gte<V: PostgrestFilterValue>(_ column: KeyPath<Relation, V>, _ value: V) -> Self {
    Self(builder: builder.gte(Relation.columnName(for: column), value: value))
  }

  /// Matches rows where the column at `column` is less than `value`.
  public func lt<V: PostgrestFilterValue>(_ column: KeyPath<Relation, V>, _ value: V) -> Self {
    Self(builder: builder.lt(Relation.columnName(for: column), value: value))
  }

  /// Matches rows where the column at `column` is less than or equal to `value`.
  public func lte<V: PostgrestFilterValue>(_ column: KeyPath<Relation, V>, _ value: V) -> Self {
    Self(builder: builder.lte(Relation.columnName(for: column), value: value))
  }

  /// Matches rows where the column at `column` is one of `values`.
  public func `in`<V: PostgrestFilterValue>(_ column: KeyPath<Relation, V>, _ values: [V]) -> Self {
    Self(builder: builder.in(Relation.columnName(for: column), values: values))
  }

  /// Matches rows where the optional column at `column` is SQL `NULL`.
  public func isNull<V>(_ column: KeyPath<Relation, V?>) -> Self {
    Self(builder: builder.filter(Relation.columnName(for: column), operator: "is", value: "null"))
  }

  /// Matches rows where the optional column at `column` is not SQL `NULL`.
  public func isNotNull<V>(_ column: KeyPath<Relation, V?>) -> Self {
    Self(
      builder: builder.filter(Relation.columnName(for: column), operator: "not.is", value: "null")
    )
  }
}

extension PostgrestTypedQuery where Phase: PostgrestTransformablePhase {
  /// Sorts the result by the column at `column`.
  ///
  /// Ordering moves the request into ``PostgrestTransformPhase``, so no further filter can be
  /// applied after it — the same rule the string-based builders follow.
  public func order<V>(
    _ column: KeyPath<R, V>,
    ascending: Bool = true,
    nullsFirst: Bool = false
  ) -> PostgrestTypedQuery<R, Output, PostgrestTransformPhase> {
    PostgrestTypedQuery<R, Output, PostgrestTransformPhase>(
      builder: builder.order(
        R.columnName(for: column), ascending: ascending, nullsFirst: nullsFirst
      )
    )
  }

  /// Limits the number of rows returned.
  ///
  /// Like ``order(_:ascending:nullsFirst:)`` this moves the request into
  /// ``PostgrestTransformPhase``.
  public func limit(_ count: Int) -> PostgrestTypedQuery<R, Output, PostgrestTransformPhase> {
    PostgrestTypedQuery<R, Output, PostgrestTransformPhase>(builder: builder.limit(count))
  }
}
