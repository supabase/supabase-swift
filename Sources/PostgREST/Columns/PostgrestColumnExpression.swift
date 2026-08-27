//
//  PostgrestColumnExpression.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

/// Anything that can appear in a `select` list: a stored column, a cast, a JSON path, an
/// aggregate, or a column projected through an embedded relation.
///
/// `@Table` generates the conformances. You do not conform your own types.
public protocol PostgrestColumnExpression<Root, Value>: Sendable {
  /// The relation this expression belongs to. Using it against another relation is a compile
  /// error.
  associatedtype Root: PostgrestRelation

  /// The Swift type this expression produces. Operators require a matching operand, so
  /// `.eq("seven")` on an `Int` column does not compile.
  associatedtype Value

  /// The text PostgREST expects, in a `select` list or on the left of an operator.
  var postgrestExpression: String { get }
}

/// A column expression that can also sit on the left of a filter operator.
///
/// Casts, aggregates and to-many embedded columns do not conform, so filtering on one is a
/// compile error rather than a request that misbehaves:
///
/// - PostgREST drops a cast from the SQL it generates, so `cost::text=eq.10` answers 200 having
///   compared the uncast column.
/// - There is no `HAVING`, so an aggregate cannot be filtered on.
/// - An embedded column filters as `orders.id` but selects as `orders(id)`; filtering inside an
///   embed is not supported yet.
public protocol PostgrestFilterableExpression<Root, Value>: PostgrestColumnExpression {}

/// A column expression that can be used as an `order` key.
///
/// Stored columns, JSON paths and to-one embedded columns conform. Casts, aggregates and to-many
/// embedded columns do not — PostgREST rejects all three in `order`.
public protocol PostgrestOrderableExpression<Root, Value>: PostgrestColumnExpression {}

/// A stored column, reached through a relation's generated `Columns` namespace.
public struct PostgrestColumn<Root: PostgrestRelation, Value>: PostgrestFilterableExpression,
  PostgrestOrderableExpression
{
  public let postgrestExpression: String

  /// - Parameter name: The database column name.
  public init(_ name: String) {
    self.postgrestExpression = name
  }
}

/// A stored column the database allows to be `NULL`.
///
/// `Value` is the **wrapped** type: `var dueDate: Date?` generates
/// `PostgrestNullableColumn<Todo, Date>`. So every operator takes a non-optional operand — use
/// ``PostgrestNullableColumn/isNull()`` to test for `NULL` — while an update accepts `nil` here
/// to clear the column.
public struct PostgrestNullableColumn<
  Root: PostgrestRelation,
  Value
>: PostgrestFilterableExpression, PostgrestOrderableExpression {
  public let postgrestExpression: String

  /// - Parameter name: The database column name.
  public init(_ name: String) {
    self.postgrestExpression = name
  }
}
