//
//  PostgrestUpdate.swift
//  PostgREST
//
//  Created by Guilherme Souza on 25/08/26.
//

import Foundation

/// The columns an update writes, and what it writes to each.
///
/// An update is a set of column assignments, not a partial row. That distinction is what lets a
/// nullable column be cleared: a column is in the request body because it was assigned, and the
/// value it carries is whatever was assigned to it. Assigning `nil` sends an explicit `null`;
/// never naming a column leaves it out of the body, and the database leaves it alone.
///
/// ```swift
/// try await client.from(Todo.self)
///   .update {
///     $0.task = "buy oat milk"   // {"task": "buy oat milk"}
///     $0.dueDate = nil           // {"due_at": null}
///   }
///   .where { $0.id.eq(1) }
///   .execute()
/// ```
///
/// A column whose property is not optional cannot be assigned `nil`, so a `NOT NULL` column
/// cannot be cleared by accident — that is a compile error, not a 400 from the server.
///
/// Assigning the same column twice keeps the last value.
@dynamicMemberLookup
public struct PostgrestUpdate<R: PostgrestWritableRelation>: Encodable, Sendable {
  private var values: [String: PostgrestUpdateValue] = [:]

  /// Builds an update from a closure that assigns to the columns it changes.
  ///
  /// Building the payload as a value, rather than only inline at the call site, is what lets one
  /// layer decide what an update changes and another layer send it.
  ///
  /// - Parameter build: A closure that assigns to the columns this update writes.
  public init(_ build: (inout PostgrestUpdate<R>) -> Void) {
    build(&self)
  }

  /// Whether this update names no columns at all.
  ///
  /// An empty update encodes to `{}`, which asks PostgREST to change nothing.
  public var isEmpty: Bool { values.isEmpty }

  /// Assigns a value to a column.
  ///
  /// Only the setter is meaningful. An update describes what to write, so there is nothing to
  /// read back, and the getter is marked unavailable rather than left to trap at runtime.
  ///
  /// This overload takes a `NOT NULL` column, so the assigned type is not optional and
  /// `$0.task = nil` is a compile error.
  ///
  /// - Parameter keyPath: A key path into the relation's ``PostgrestRelation/Columns`` namespace,
  ///   the same place a filter reads a column name from.
  public subscript<V: Encodable & Sendable>(
    dynamicMember keyPath: KeyPath<R.Columns, PostgrestColumn<R, V>>
  ) -> V {
    @available(
      *, unavailable,
      message: "An update names the columns it writes; it does not read them back."
    )
    get { fatalError("PostgrestUpdate is write-only") }
    set {
      values[R.columns[keyPath: keyPath].postgrestExpression] = PostgrestUpdateValue(newValue)
    }
  }

  /// Assigns a value to a nullable column, or clears it.
  ///
  /// The assigned type is optional, so `$0.dueAt = nil` sends an explicit `null` and clears the
  /// column, rather than omitting it from the body.
  ///
  /// - Parameter keyPath: A key path to one of the relation's nullable columns.
  public subscript<V: Encodable & Sendable>(
    dynamicMember keyPath: KeyPath<R.Columns, PostgrestNullableColumn<R, V>>
  ) -> V? {
    @available(
      *, unavailable,
      message: "An update names the columns it writes; it does not read them back."
    )
    get { fatalError("PostgrestUpdate is write-only") }
    set {
      values[R.columns[keyPath: keyPath].postgrestExpression] = PostgrestUpdateValue(newValue)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: PostgrestUpdateColumnKey.self)
    for (column, value) in values {
      // Not `encodeIfPresent`. An assigned `nil` reaches here as a boxed `Optional.none`, and
      // this call routes it to `encodeNil`, which is the explicit `null` on the wire. The
      // synthesized `Encodable` of a struct with optional fields calls `encodeIfPresent`
      // instead, which is exactly why the previous `Update` row shape could not clear a column.
      try container.encode(value, forKey: PostgrestUpdateColumnKey(column))
    }
  }
}

/// One assigned value, kept behind an existential so a single payload can hold columns of
/// different types.
struct PostgrestUpdateValue: Encodable, Sendable {
  private let value: any Encodable & Sendable

  init(_ value: any Encodable & Sendable) {
    self.value = value
  }

  func encode(to encoder: any Encoder) throws {
    try value.encode(to: encoder)
  }
}

/// A coding key for a column name that is only known at runtime.
struct PostgrestUpdateColumnKey: CodingKey {
  let stringValue: String

  init(_ stringValue: String) {
    self.stringValue = stringValue
  }

  init?(stringValue: String) {
    self.stringValue = stringValue
  }

  var intValue: Int? { nil }

  init?(intValue: Int) { nil }
}
