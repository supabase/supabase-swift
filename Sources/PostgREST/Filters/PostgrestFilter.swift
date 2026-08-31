//
//  PostgrestFilter.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

import Foundation
import Helpers

/// A filter on a relation.
///
/// Built inside a `where` closure by calling an operator method on a column, then composing the
/// results with `&&`, `||` and `!`:
///
/// ```swift
/// try await client.from(Todo.self)
///   .select()
///   .where { ($0.isDone.eq(false) && $0.priority.gt(3)) || $0.id.eq(7) }
///   .execute()
/// ```
///
/// A top-level `&&` renders as separate query parameters, `||` as one `or=(…)`, and an `&&`
/// nested inside an `||` as `and(…)`.
public struct PostgrestFilter<R: PostgrestRelation>: Sendable {
  indirect enum Node: Sendable {
    case comparison(column: String, operator: String, value: String)

    /// Everything after the `=` as one unparsed string. Separate from `comparison` because the
    /// operator and value cannot be split.
    case raw(column: String, operand: String)

    case and([Node])
    case or([Node])
    case not(Node)
  }

  var node: Node

  init(node: Node) {
    self.node = node
  }

  init(column: String, operator: String, value: String) {
    self.node = .comparison(column: column, operator: `operator`, value: value)
  }

  init(rawColumn: String, operand: String) {
    self.node = .raw(column: rawColumn, operand: operand)
  }

  /// A filter written entirely in PostgREST syntax, for an expression the generated namespace
  /// cannot name.
  ///
  /// Nothing here is checked. Prefer ``PostgrestFilterableExpression/raw(_:)``, which keeps the
  /// column compiler-checked and takes only the operand as a string.
  ///
  /// ```swift
  /// .where { $0.isDone.eq(false) && .raw("cost::text", "eq.10") }
  /// ```
  ///
  /// > Important: Keep a raw node out of every subtree beneath `||` or `!`, not merely out of
  /// > their immediate operands. Anything below one of those renders in the stricter
  /// > `or=(…)`/`not.and=(…)` grammar, where a `::` in the column name is a `PGRST100` even
  /// > though it parses at top level. The immediate combinator does not decide it:
  /// > `(a && .raw("cost::text", "eq.10")) || b` renders
  /// > `or=(and(a,cost::text.eq.10),b)` and 400s, and `!(a && .raw("cost::text", "eq.10"))`
  /// > renders `not.and=(a,cost::text.eq.10)` and 400s the same way. Only a node whose path to
  /// > the root is `&&` throughout stays in the top-level grammar.
  ///
  /// - Parameters:
  ///   - column: The query-parameter name, for example `"cost::text"`.
  ///   - operand: Everything after the `=`, for example `"eq.10"`.
  public static func raw(_ column: String, _ operand: String) -> Self {
    Self(rawColumn: column, operand: operand)
  }

  enum Junction { case and, or }

  /// Merges two nodes under one junction, absorbing a child of the same kind, so `a || b || c`
  /// renders as one flat `or=(a,b,c)` rather than `or=(or(a,b),c)`.
  static func flatten(_ lhs: Node, _ rhs: Node, as junction: Junction) -> [Node] {
    func parts(_ node: Node) -> [Node] {
      switch (junction, node) {
      case (.and, .and(let children)): return children
      case (.or, .or(let children)): return children
      default: return [node]
      }
    }
    return parts(lhs) + parts(rhs)
  }
}

// MARK: - Composition

/// Matches rows satisfying both filters.
public func && <R>(lhs: PostgrestFilter<R>, rhs: PostgrestFilter<R>) -> PostgrestFilter<R> {
  PostgrestFilter(node: .and(PostgrestFilter<R>.flatten(lhs.node, rhs.node, as: .and)))
}

/// Matches rows satisfying either filter.
public func || <R>(lhs: PostgrestFilter<R>, rhs: PostgrestFilter<R>) -> PostgrestFilter<R> {
  PostgrestFilter(node: .or(PostgrestFilter<R>.flatten(lhs.node, rhs.node, as: .or)))
}

/// Matches rows that do not satisfy `operand`.
prefix public func ! <R>(operand: PostgrestFilter<R>) -> PostgrestFilter<R> {
  PostgrestFilter(node: .not(operand.node))
}

// MARK: - Rendering

extension PostgrestFilter {
  /// The query items this filter contributes to a request.
  func queryItems() -> [URLQueryItem] {
    Self.queryItems(for: node)
  }

  private static func queryItems(for node: Node) -> [URLQueryItem] {
    switch node {
    case .comparison(let column, let `operator`, let value):
      return [URLQueryItem(name: column, value: "\(`operator`).\(value)")]

    case .raw(let column, let operand):
      return [URLQueryItem(name: column, value: operand)]

    case .and(let children):
      // PostgREST ANDs separate parameters, so a top-level AND needs no grouping.
      return children.flatMap { queryItems(for: $0) }

    case .or(let children):
      return [URLQueryItem(name: "or", value: "(\(children.map(group).joined(separator: ",")))")]

    case .not(let inner):
      switch inner {
      case .and(let children):
        return [
          URLQueryItem(name: "not.and", value: "(\(children.map(group).joined(separator: ",")))")
        ]
      case .or(let children):
        return [
          URLQueryItem(name: "not.or", value: "(\(children.map(group).joined(separator: ",")))")
        ]
      case .comparison(let column, let `operator`, let value):
        return [URLQueryItem(name: column, value: "not.\(`operator`).\(value)")]
      case .raw(let column, let operand):
        return [URLQueryItem(name: column, value: "not.\(operand)")]
      case .not(let doubleNegated):
        return queryItems(for: doubleNegated)
      }
    }
  }

  /// A node in the comma-separated form used inside `or=(…)`, where the grammar differs from
  /// top level. Each rule below is a 400 or a silent zero-row answer if broken:
  ///
  /// - An AND is spelled `and(…)`; there is no parameter separator to carry the meaning.
  /// - Operands must be escaped. `or=(name.eq.p(q),id.eq.3)` answers 200 with zero rows.
  /// - A negated leaf puts `not.` after the column (`id.not.eq.2`); `not.` may only precede
  ///   `and`/`or` here. Negating a whole group is unaffected.
  /// - Double negation must collapse, or `!!a || b` renders `not.not.` and 400s.
  private static func group(_ node: Node) -> String {
    switch node {
    case .comparison(let column, let `operator`, let value):
      return "\(column).\(`operator`).\(escapePostgRESTFilterValue(value))"
    case .raw(let column, let operand):
      // Not escaped: quoting would break the caller's own syntax. The cost is that a raw node
      // cannot always sit in a group — a `::` in the column is a parse error inside `or=(…)`.
      return "\(column).\(operand)"
    case .and(let children):
      return "and(\(children.map(group).joined(separator: ",")))"
    case .or(let children):
      return "or(\(children.map(group).joined(separator: ",")))"
    case .not(let inner):
      switch inner {
      case .not(let doubleNegated):
        return group(doubleNegated)
      case .and, .or:
        // `not.` in front of a group is the only spelling PostgREST accepts here.
        return "not.\(group(inner))"
      case .comparison(let column, let `operator`, let value):
        return "\(column).not.\(`operator`).\(escapePostgRESTFilterValue(value))"
      case .raw(let column, let operand):
        return "\(column).not.\(operand)"
      }
    }
  }
}
