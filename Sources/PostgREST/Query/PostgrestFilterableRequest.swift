//
//  PostgrestFilterableRequest.swift
//  PostgREST
//
//  Created by Guilherme Souza on 21/08/26.
//

/// A request that can be scoped by a filter.
///
/// ``PostgrestQuery`` and ``PostgrestMutation`` conform, so ``where(_:)`` is declared once here.
/// You do not conform your own types to this.
///
/// Not to be confused with ``PostgrestFilterableExpression``, which is a *column* that can sit on
/// the left of an operator, or ``PostgrestFilterablePhase``, a phase marker on the string builder.
///
/// > Warning: Part of the typed query API, which is alpha. Its shape may change in a minor release.
public protocol PostgrestFilterableRequest {
  /// The relation whose columns this request accepts.
  associatedtype Relation: PostgrestRelation

  /// The request that gets sent, and that a filter is added to.
  var request: PostgrestRequest { get set }
}
