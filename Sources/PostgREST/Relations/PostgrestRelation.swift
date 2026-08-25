//
//  PostgrestRelation.swift
//  PostgREST
//
//  Created by Guilherme Souza on 21/08/26.
//

/// A shape that can be selected from a relation.
///
/// Conformance is normally synthesized by the `@Table` or `@SelectionOf` macro in the
/// `PostgrestMacros` module, or emitted by the schema generator. Hand-written conformances are
/// supported and are the escape hatch when neither fits.
public protocol PostgrestSelection: Decodable, Sendable {
  /// The relation this shape selects from.
  ///
  /// Naming the source is what stops a selection being handed to the wrong relation. A relation is
  /// its own source, fixed by the same-type constraint on ``PostgrestRelation``, so a hand-written
  /// relation conformance declares nothing here.
  associatedtype Source: PostgrestRelation

  /// The PostgREST `select` expression for this shape, for example `"id,task"`.
  static var selectString: String { get }
}

/// A queryable source of rows: a table, a view, or a materialized view.
///
/// "Relation" is Postgres's own term for that family. Selecting a whole row is the degenerate
/// selection, which is why this refines ``PostgrestSelection``.
public protocol PostgrestRelation: PostgrestSelection where Source == Self {
  /// The relation's name as PostgREST addresses it.
  static var relationName: String { get }

  /// The Postgres schema the relation belongs to.
  static var schema: String { get }

  /// The database column name backing a property.
  ///
  /// - Parameter keyPath: A key path to one of this type's stored properties.
  /// - Returns: The column name PostgREST expects in a query string.
  static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String
}

/// A relation the database accepts writes for: a table, or a view Postgres reports as updatable.
///
/// `Insert` and `Update` have no defaults on purpose. Defaulting them to `Self` would mean
/// requiring every column on both — including the ones the database fills in on insert, and the
/// ones an update is not touching.
public protocol PostgrestWritableRelation: PostgrestRelation {
  /// The shape accepted by an insert: every column, optional exactly where the database can fill
  /// it in — a nullable column, or one with a default. A primary key is included, and required
  /// unless it is also defaulted.
  associatedtype Insert: Encodable & Sendable

  /// The shape accepted by an update: every column optional.
  associatedtype Update: Encodable & Sendable
}
