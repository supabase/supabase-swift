//
//  PostgrestQuery+Where.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

import Foundation
import Helpers

extension PostgrestFilterableRequest {
  /// Scopes the request by a filter.
  ///
  /// The closure receives the relation's column namespace. Each PostgREST operator is a method
  /// on a column, and `&&`, `||` and `!` compose the results:
  ///
  /// ```swift
  /// try await client.from(Todo.self)
  ///   .select()
  ///   .where { ($0.isDone.eq(false) && $0.priority.gt(3)) || $0.id.eq(7) }
  ///   .execute()
  /// ```
  ///
  /// A filter that depends on runtime state is assembled in the closure body like any other
  /// value:
  ///
  /// ```swift
  /// .where { c in
  ///   var filter = c.isDone.eq(false)
  ///   if let priority { filter = filter && c.priority.gte(priority) }
  ///   return filter
  /// }
  /// ```
  ///
  /// > Note: Two `where` calls accumulate — they are ANDed; neither replaces the other.
  ///
  /// - Parameter build: Builds the filter from the relation's columns.
  /// - Returns: A new request with the filter applied. The receiver is unchanged.
  public func `where`(_ build: (Relation.Columns) -> PostgrestFilter<Relation>) -> Self {
    var filtered = self
    filtered.request.query.append(contentsOf: build(Relation.columns).queryItems())
    return filtered
  }
}

extension PostgrestQuery {
  /// Sorts the result.
  ///
  /// The direction is spelled on the column, the same way an operator is:
  ///
  /// ```swift
  /// .order { $0.dueDate.asc() }
  /// .order { $0.priority.desc().nulls(.first) }
  /// ```
  ///
  /// Repeated calls append, so the second key breaks ties in the first.
  ///
  /// - Parameter build: Builds the sort key from the relation's columns.
  public func order(
    _ build: (R.Columns) -> PostgrestOrdering<R>
  ) -> Self {
    appendingOrder(build(R.columns).rendered)
  }

  /// Sorts by a column expression, leaving the direction to PostgREST.
  ///
  /// ```swift
  /// .order { $0.dueDate }                  // order=due_at
  /// .order { $0.priority.desc() }          // order=priority.desc
  /// .order { $0.dueDate.nulls(.first) }    // order=due_at.nullsfirst
  /// ```
  ///
  /// Chain ``PostgrestOrderableExpression/asc()`` or ``PostgrestOrderableExpression/desc()`` when
  /// the direction matters. Direction and placement are independent on the wire, so
  /// ``PostgrestOrderableExpression/nulls(_:)`` sets a placement without choosing one.
  public func order<E: PostgrestOrderableExpression>(
    _ build: (R.Columns) -> E
  ) -> Self where E.Root == R {
    appendingOrder(
      PostgrestOrdering<R>(column: build(R.columns).postgrestExpression, ascending: nil).rendered
    )
  }

  /// Merges one rendered sort key into the single `order` parameter PostgREST expects.
  ///
  /// A merge, not a second parameter: PostgREST honours only the first `order` it sees and
  /// silently ignores the rest, so `order=name.asc&order=id.desc` sorts by name alone. Only
  /// `order=name.asc,id.desc` applies both.
  ///
  private func appendingOrder(_ value: String) -> Self {
    var query = self
    if let index = query.request.query.firstIndex(where: { $0.name == "order" }),
      let existing = query.request.query[index].value
    {
      query.request.query[index] = URLQueryItem(name: "order", value: "\(existing),\(value)")
    } else {
      query.request.query.append(URLQueryItem(name: "order", value: value))
    }
    return query
  }

  /// Limits the number of rows returned.
  public func limit(_ count: Int) -> Self {
    var query = self
    query.request.query.appendOrUpdate(URLQueryItem(name: "limit", value: "\(count)"))
    return query
  }

  /// Returns only the rows within the zero-based, inclusive index range.
  ///
  /// `range(10...19)` is the second page of ten.
  public func range(_ bounds: ClosedRange<Int>) -> Self {
    var query = self
    query.request.query.appendOrUpdate(
      URLQueryItem(name: "offset", value: "\(bounds.lowerBound)"))
    query.request.query.appendOrUpdate(URLQueryItem(name: "limit", value: "\(bounds.count)"))
    return query
  }
}
