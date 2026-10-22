//
//  PostgrestFilterableRequest.swift
//  PostgREST
//
//  Created by Guilherme Souza on 21/08/26.
//

/// A request that can be scoped by a filter.
///
/// ``_PostgrestQuery`` conforms, and so does a ``_PostgrestMutation`` in ``_PostgrestScopedPhase``, so
/// ``where(_:)`` is declared once here.
/// You do not conform your own types to this.
///
/// Not to be confused with ``_PostgrestFilterableExpression``, which is a *column* that can sit on
/// the left of an operator, or ``PostgrestFilterablePhase``, a phase marker on the string builder.
///
/// > Warning: Part of the typed query API, which is experimental. Its shape may change in a minor
/// > release. Opt in with `@_spi(Experimental) import Supabase`.
public protocol _PostgrestFilterableRequest {
  /// The relation whose columns this request accepts.
  associatedtype Relation: _PostgrestRelation

  /// The request that gets sent, and that a filter is added to.
  var request: _PostgrestRequest { get set }
}
