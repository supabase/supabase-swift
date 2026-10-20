//
//  PostgrestFilter.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

import Foundation
import Helpers

indirect enum PostgrestFilterNode: Sendable {
  enum Operand: Sendable {
    case value(String)

    /// The members of the `(a,b)` list `in` takes, each as its raw value. Members are quoted in
    /// every position, with the filter escaper rather than the array one: an `in.(…)` list is
    /// filter-value syntax, and with the array escaper `name=in.(p(q),Ada)` answers 200 with
    /// zero rows. The list's own parentheses are the operator's grammar and are never quoted.
    case list([String])

    case `is`(Bool?)

    case invalid(String)

    static func typed(_ value: some PostgrestFilterValue) -> Self {
      value._typedOperand.map(Self.value) ?? .invalid(Self.noWireForm(value))
    }

    static func typedList<V: PostgrestFilterValue>(_ values: [V]) -> Self {
      var members: [String] = []
      for value in values {
        guard let member = value._typedOperand else { return .invalid(Self.noWireForm(value)) }
        members.append(member)
      }
      return .list(members)
    }

    private static func noWireForm(_ value: some PostgrestFilterValue) -> String {
      "\(value) has no wire form, so the filter cannot be sent."
    }
  }

  case comparison(column: String, operator: _PostgrestFilterOperator, operand: Operand)

  case raw(column: String, operand: String)

  case and([PostgrestFilterNode])
  case or([PostgrestFilterNode])
  case not(PostgrestFilterNode)

}

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
///
/// The six comparisons also have operator spellings that build the same filter:
/// `$0.priority > 3` is `$0.priority.gt(3)`, and `$0.dueDate == nil` is `$0.dueDate.isNull()`.
public struct _PostgrestFilter<R: _PostgrestRelation>: Sendable {
  typealias Node = PostgrestFilterNode
  typealias Operand = PostgrestFilterNode.Operand

  var node: Node

  init(node: Node) {
    self.node = node
  }

  init(column: String, operator: _PostgrestFilterOperator, value: some PostgrestFilterValue) {
    self.node = .comparison(column: column, operator: `operator`, operand: .typed(value))
  }

  init(column: String, operator: _PostgrestFilterOperator, operand: Operand) {
    self.node = .comparison(column: column, operator: `operator`, operand: operand)
  }

  init(rawColumn: String, operand: String) {
    self.node = .raw(column: rawColumn, operand: operand)
  }

  /// A filter written entirely in PostgREST syntax, for an expression the generated namespace
  /// cannot name.
  ///
  /// Nothing here is checked. Prefer ``_PostgrestFilterableExpression/raw(_:)``, which keeps the
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

/// Matches rows satisfying both filters.
public func && <R>(lhs: _PostgrestFilter<R>, rhs: _PostgrestFilter<R>) -> _PostgrestFilter<R> {
  _PostgrestFilter(node: .and(_PostgrestFilter<R>.flatten(lhs.node, rhs.node, as: .and)))
}

/// Matches rows satisfying either filter.
public func || <R>(lhs: _PostgrestFilter<R>, rhs: _PostgrestFilter<R>) -> _PostgrestFilter<R> {
  _PostgrestFilter(node: .or(_PostgrestFilter<R>.flatten(lhs.node, rhs.node, as: .or)))
}

/// Matches rows that do not satisfy `operand`.
prefix public func ! <R>(operand: _PostgrestFilter<R>) -> _PostgrestFilter<R> {
  _PostgrestFilter(node: .not(operand.node))
}

extension PostgrestFilterNode.Operand {
  var topLevel: String {
    switch self {
    case .value(let raw):
      return raw
    case .list(let members):
      return "(\(members.map(escapePostgRESTFilterValue).joined(separator: ",")))"
    case .is(let bool):
      return bool.map { "\($0)" } ?? "null"
    case .invalid:
      return ""
    }
  }

  /// The operand as sent inside `or=(…)`, where a bare `,` or `)` in a value ends the group early.
  /// Only a single value gains quoting here: list members are quoted in every position already,
  /// and an `IS` keyword never is.
  var grouped: String {
    switch self {
    case .value(let raw):
      return escapePostgRESTFilterValue(raw)
    case .list, .is, .invalid:
      return topLevel
    }
  }
}

extension _PostgrestFilter {
  func queryItems() -> [URLQueryItem] {
    node.queryItems()
  }

  var invalidFilterReason: String? {
    node.invalidFilterReason
  }
}

extension PostgrestFilterNode {
  var invalidFilterReason: String? {
    switch self {
    case .comparison(_, _, .invalid(let reason)): reason
    case .comparison, .raw: nil
    case .and(let children), .or(let children):
      children.lazy.compactMap(\.invalidFilterReason).first
    case .not(let inner): inner.invalidFilterReason
    }
  }
}

extension PostgrestFilterNode {
  func queryItems() -> [URLQueryItem] {
    Self.queryItems(for: self)
  }

  private static func queryItems(for node: Self) -> [URLQueryItem] {
    switch node {
    case .comparison(let column, let `operator`, let operand):
      return [URLQueryItem(name: column, value: "\(`operator`.token).\(operand.topLevel)")]

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
      case .comparison(let column, let `operator`, let operand):
        return [
          URLQueryItem(name: column, value: "not.\(`operator`.token).\(operand.topLevel)")
        ]
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
  private static func group(_ node: Self) -> String {
    switch node {
    case .comparison(let column, let `operator`, let operand):
      return "\(column).\(`operator`.token).\(operand.grouped)"
    case .raw(let column, let operand):
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
      case .comparison(let column, let `operator`, let operand):
        return "\(column).not.\(`operator`.token).\(operand.grouped)"
      case .raw(let column, let operand):
        return "\(column).not.\(operand)"
      }
    }
  }
}
