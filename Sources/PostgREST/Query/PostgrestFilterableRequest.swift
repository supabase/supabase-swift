//
//  PostgrestFilterableRequest.swift
//  PostgREST
//
//  Created by Guilherme Souza on 21/08/26.
//

/// A request that can be scoped by a filter.
///
/// ``PostgrestTypedQuery`` and ``PostgrestTypedMutation`` conform, so ``where(_:)`` is declared
/// once here. You do not conform your own types to this.
///
/// Only filtering lives here: `order` and `limit` move the request into
/// ``PostgrestTransformPhase``, so they cannot return `Self` and are declared on
/// ``PostgrestTypedQuery`` instead.
///
/// Not to be confused with ``PostgrestFilterableExpression``, which is a *column* that can sit on
/// the left of an operator, or ``PostgrestFilterablePhase``, a phase marker on the string builder.
public protocol PostgrestFilterableRequest {
  /// The relation whose columns this wrapper accepts.
  associatedtype Relation: PostgrestRelation

  /// The phase of the underlying request. Filters require a filterable phase.
  associatedtype Phase: PostgrestFilterablePhase

  /// The underlying string-based builder.
  var builder: PostgrestRequestBuilder<Phase> { get }

  /// Wraps a builder, preserving the wrapper's type.
  init(builder: PostgrestRequestBuilder<Phase>)
}

extension PostgrestTypedQuery: PostgrestFilterableRequest where Phase: PostgrestFilterablePhase {
  public typealias Relation = R
}
