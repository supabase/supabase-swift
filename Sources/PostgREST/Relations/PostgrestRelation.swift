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
  /// Takes a `PartialKeyPath` rather than a `KeyPath<Self, V>` because the property's type
  /// is not part of the answer — a column name is a column name. Callers that do care about the
  /// type, every filter among them, constrain it in their own signature and pass the key path
  /// straight through; `KeyPath` is a `PartialKeyPath` subclass, so that costs nothing at the call
  /// site.
  ///
  /// - Parameter keyPath: A key path to one of this type's stored properties.
  /// - Returns: The column name PostgREST expects in a query string.
  static func columnName(for keyPath: PartialKeyPath<Self>) -> String
}

/// A relation that declares a primary key.
///
/// Conformance is what makes the key-derived operations available, so it is deliberately a separate
/// protocol rather than an optional member on ``PostgrestRelation``: a relation with no key does
/// not conform, and reaching for one of those operations on it is *no such overload* instead of a
/// request the database cannot honor.
///
/// `@Table` conforms a type to this whenever a property is marked `@PrimaryKey`. A hand-written
/// conformance opts in by declaring ``primaryKeyColumns``.
public protocol PostgrestKeyedRelation: PostgrestRelation {
  /// The columns making up the relation's primary key, in declaration order.
  ///
  /// There is no default. An empty array would conform a keyless relation and let it derive an
  /// empty `on_conflict`, which is a different request rather than a missing one — so "declares no
  /// key" is spelled as not conforming at all.
  static var primaryKeyColumns: [String] { get }
}

/// A relation the database accepts writes for: a table, or a view Postgres reports as updatable.
///
/// `Insert` has no default on purpose. Defaulting it to `Self` would mean requiring every column,
/// including the ones the database fills in.
///
/// There is no matching `Update` shape. An insert sends a row, so a row type fits it; an update
/// sends a set of column assignments, which ``PostgrestUpdate`` builds from this relation's key
/// paths. Modelling both as row types is what once made clearing a nullable column impossible —
/// a single optional field cannot mean both "not assigned" and "assigned null".
public protocol PostgrestWritableRelation: PostgrestRelation {
  /// The shape accepted by an insert: every column, optional exactly where the database can fill
  /// it in — a nullable column, or one with a default. A primary key is included, and required
  /// unless it is also defaulted.
  associatedtype Insert: Encodable & Sendable
}
