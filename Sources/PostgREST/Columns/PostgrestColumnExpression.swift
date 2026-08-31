//
//  PostgrestColumnExpression.swift
//  PostgREST
//
//  Created by Guilherme Souza on 26/08/26.
//

// MARK: - Positions

/// Where an expression is allowed to appear. Carried as a phantom type so a derived expression
/// inherits its receiver's positions instead of restating them.
public protocol PostgrestPosition: Sendable {}

/// A position set that includes `order`.
public protocol PostgrestOrderablePosition: PostgrestPosition {}

/// A position set that includes the left of a filter operator.
public protocol PostgrestFilterablePosition: PostgrestPosition {}

/// `select` only — a cast, an aggregate, or any projection of a to-many embed.
public enum PostgrestSelectOnly: PostgrestPosition {}

/// `select` and `order`, but not a filter — a to-one embedded projection.
public enum PostgrestSelectAndOrder: PostgrestOrderablePosition {}

/// Every position — a stored column, or a JSON path on one.
public enum PostgrestEveryPosition: PostgrestOrderablePosition, PostgrestFilterablePosition {}

// MARK: - Expressions

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

  /// Where this expression may appear. A derivation of it inherits this, so a JSON path on a
  /// to-many embed is select-only without that rule being written per embed kind.
  associatedtype Position: PostgrestPosition

  /// The text PostgREST expects, in a `select` list or on the left of an operator.
  var postgrestExpression: String { get }

  /// Applies `derivation` where PostgREST expects it, which is not always at the end: an
  /// embedded projection renders `parent(title)`, and a cast or aggregate has to land inside
  /// those parentheses or the server drops it.
  ///
  /// This is the single hook each expression kind implements. Every accessor — `cast(to:)`,
  /// `jsonText(_:)`, `sum()` and the rest — is declared once against it.
  func _deriving<V, P: PostgrestPosition>(
    _ derivation: String
  ) -> PostgrestDerivedExpression<Root, V, P>
}

extension PostgrestColumnExpression {
  /// Appends, which is correct for everything that is not an embedded projection.
  public func _deriving<V, P: PostgrestPosition>(
    _ derivation: String
  ) -> PostgrestDerivedExpression<Root, V, P> {
    PostgrestDerivedExpression(embed: nil, inner: postgrestExpression + derivation)
  }
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

/// A filterable expression whose value the database allows to be `NULL`.
///
/// Carries ``PostgrestNullableExpression/isNull()``, which is meaningless on a `NOT NULL` column:
/// it can never match, and a filter that silently returns nothing is worse than one that does not
/// compile.
///
/// This is a protocol rather than a member of one concrete column type so that a future nullable
/// expression — a JSON path into a nullable column, an outer-joined embed — gets `isNull()` by
/// conforming, instead of the operator having to be redeclared on it.
public protocol PostgrestNullableExpression<Root, Value>: PostgrestFilterableExpression {}

// MARK: - Nullability

/// Whether a stored column's database type admits `NULL`.
///
/// A phantom type on ``PostgrestStoredColumn``, never a value and never on the wire: it exists so
/// one struct serves both column kinds while `isNull()` and an update's `nil` assignment stay
/// available on exactly the nullable one.
public protocol PostgrestNullability: Sendable {}

/// A `NOT NULL` column.
public enum PostgrestNotNull: PostgrestNullability {}

/// A column the database allows to be `NULL`.
public enum PostgrestNullable: PostgrestNullability {}

/// A stored column, reached through a relation's generated `Columns` namespace.
///
/// Spell it as ``PostgrestColumn`` or ``PostgrestNullableColumn`` rather than naming this type
/// directly; both are aliases that fix `Nullability`.
///
/// `Value` is always the **wrapped** type: `var dueDate: Date?` generates
/// `PostgrestNullableColumn<Todo, Date>`, not `Optional<Date>`. So every operator takes a
/// non-optional operand — use ``PostgrestNullableExpression/isNull()`` to test for `NULL` — while
/// an update accepts `nil` on a nullable column to clear it.
public struct PostgrestStoredColumn<
  Root: PostgrestRelation,
  Value,
  Nullability: PostgrestNullability
>: PostgrestFilterableExpression, PostgrestOrderableExpression {
  public typealias Position = PostgrestEveryPosition

  public let postgrestExpression: String

  /// - Parameter name: The database column name.
  public init(_ name: String) {
    self.postgrestExpression = name
  }
}

/// Only a nullable column can be `NULL`, so only it gets `isNull()`.
extension PostgrestStoredColumn: PostgrestNullableExpression
where Nullability == PostgrestNullable {}

/// A stored `NOT NULL` column.
public typealias PostgrestColumn<Root: PostgrestRelation, Value> =
  PostgrestStoredColumn<Root, Value, PostgrestNotNull>

/// A stored column the database allows to be `NULL`.
public typealias PostgrestNullableColumn<Root: PostgrestRelation, Value> =
  PostgrestStoredColumn<Root, Value, PostgrestNullable>
