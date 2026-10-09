//
//  PostgrestEmbeddedScope.swift
//  PostgREST
//
//  Created by Guilherme Souza on 06/10/26.
//

import Foundation
import IssueReporting

// MARK: - Declaration

/// An embed a selection declares, as `@SelectionOf` records a `@Relationship` property.
///
/// Three facts make an embed addressable, and a scope needs all three: the alias the response
/// comes back under, the name PostgREST addresses the embed by, and the embedded selection, which
/// gives the nested select list.
///
/// > Warning: Part of the typed query API, which is experimental. Its shape may change in a minor
/// > release. Opt in with `@_spi(Experimental) import Supabase`.
public struct _PostgrestEmbed<Selection: _PostgrestSelection>: Sendable {
  /// The name the response carries the embed under, and the prefix of every scoped parameter.
  ///
  /// PostgREST accepts an alias in place of the resource name in `comments.limit=5`, so one
  /// name serves both.
  public let alias: String

  /// What PostgREST addresses the embed by: `comments!todo_id` for a foreign-key relationship,
  /// `get_messages` for a computed one.
  let embedName: String

  /// An embed that follows a foreign key.
  ///
  /// The key is always sent as the `!todo_id` hint: omitting it on an ambiguous relationship is
  /// HTTP 300 `PGRST201`.
  ///
  /// - Parameters:
  ///   - alias: The name the response carries the embed under.
  ///   - foreignKey: The foreign-key column the join follows.
  public init(alias: String, foreignKey: String) {
    self.alias = alias
    self.embedName = "\(Selection.Source.relationName)!\(foreignKey)"
  }

  /// An embed through a to-many computed relationship: a set-returning function whose only
  /// argument is the parent's row type. PostgREST addresses it by the function name, with no
  /// foreign-key hint.
  ///
  /// - Parameters:
  ///   - alias: The name the response carries the embed under.
  ///   - relation: The relationship, as declared on the parent's `Columns` namespace.
  public init<Root>(alias: String, relation: _PostgrestToManyRelation<Root, Selection.Source>) {
    self.alias = alias
    self.embedName = relation.postgrestEmbedName
  }

  /// An embed through a to-one computed relationship: a function returning one row of
  /// `Selection.Source`, whose only argument is the parent's row type.
  ///
  /// - Parameters:
  ///   - alias: The name the response carries the embed under.
  ///   - relation: The relationship, as declared on the parent's `Columns` namespace.
  public init<Root>(alias: String, relation: _PostgrestToOneRelation<Root, Selection.Source>) {
    self.alias = alias
    self.embedName = relation.postgrestEmbedName
  }

  /// The embed's `select` entry after its alias, `comments!todo_id(id:id,body:body)`.
  public var postgrestExpression: String {
    "\(embedName)(\(Selection.selectString))"
  }

  /// Everything up to the opening parenthesis, `comments:comments!todo_id`. A `requiring` scope
  /// finds the entry in the rendered `select` by this, then adds `!inner` before the `(`.
  var selectEntryHead: String {
    "\(alias):\(embedName)"
  }
}

/// A selection that declares at least one embed.
///
/// `@SelectionOf` conforms a type to this whenever a property carries `@Relationship`, and emits
/// the ``Embeds`` namespace with one ``_PostgrestEmbed`` per such property. A relation never
/// conforms — a whole-row select declares no embeds — which is what keeps
/// ``_PostgrestQuery/embedded(_:_:)`` and ``_PostgrestQuery/requiring(_:_:)`` off a plain
/// `select()`: there is nothing there to scope.
///
/// > Warning: Part of the typed query API, which is experimental. Its shape may change in a minor
/// > release. Opt in with `@_spi(Experimental) import Supabase`.
public protocol _PostgrestEmbeddingSelection: _PostgrestSelection {
  /// The namespace of this selection's embeds, one ``_PostgrestEmbed`` per `@Relationship`.
  associatedtype Embeds: Sendable

  /// The selection's embeds, for naming one in ``_PostgrestQuery/embedded(_:_:)``.
  static var embeds: Embeds { get }
}

// MARK: - Scope

/// Filters, sort keys and a row window applied inside one embed.
///
/// Built in the closure passed to ``_PostgrestQuery/embedded(_:_:)`` or
/// ``_PostgrestQuery/requiring(_:_:)``. Everything here targets the embedded *relation*, not the
/// nested selection, so a column the selection leaves out is still filterable:
///
/// ```swift
/// .requiring(\.comments) {
///   $0.where { $0.approved.eq(true) || $0.authorID.eq(me) }
///     .order { $0.createdAt.desc() }
///     .limit(5)
/// }
/// ```
///
/// Scoping lives on the query rather than inside the filter tree because PostgREST cannot OR a
/// parent filter against an embedded one — they are separate query parameters and always AND.
/// Keeping them apart in the types means that combination cannot be written.
///
/// > Warning: Part of the typed query API, which is experimental. Its shape may change in a minor
/// > release. Opt in with `@_spi(Experimental) import Supabase`.
public struct _PostgrestEmbeddedScope<S: _PostgrestSelection>: Sendable {
  /// The scope's parameters, named relative to this embed: `approved`, `or`, `order`, `limit`.
  var items: [URLQueryItem] = []

  /// Nested embeds to mark `!inner`, each as the chain of select-entry heads leading to it,
  /// relative to this embed's own entry.
  var innerEntries: [[String]] = []

  /// Narrows the embedded rows by a filter. Two calls AND together.
  public func `where`(_ build: (S.Source.Columns) -> _PostgrestFilter<S.Source>) -> Self {
    var scope = self
    scope.items.append(contentsOf: build(S.Source.columns).queryItems())
    return scope
  }

  /// Sorts the embedded rows. Repeated calls append, so the second key breaks ties in the first.
  public func order(_ build: (S.Source.Columns) -> _PostgrestOrdering<S.Source>) -> Self {
    var scope = self
    scope.items.mergeOrder(build(S.Source.columns).rendered)
    return scope
  }

  /// Sorts the embedded rows by a column expression, leaving the direction to PostgREST.
  public func order<E: _PostgrestOrderableExpression>(
    _ build: (S.Source.Columns) -> E
  ) -> Self where E.Root == S.Source {
    order { _PostgrestOrdering(column: build($0).postgrestExpression, ascending: nil) }
  }

  /// Limits the number of embedded rows per parent.
  public func limit(_ count: Int) -> Self {
    var scope = self
    scope.items.appendOrUpdate(URLQueryItem(name: "limit", value: "\(count)"))
    return scope
  }

  /// Returns only the embedded rows within the zero-based, inclusive index range, per parent.
  public func range(_ bounds: ClosedRange<Int>) -> Self {
    var scope = self
    scope.items.appendOrUpdate(URLQueryItem(name: "offset", value: "\(bounds.lowerBound)"))
    scope.items.appendOrUpdate(URLQueryItem(name: "limit", value: "\(bounds.count)"))
    return scope
  }

  /// Folds a nested scope into this one, prefixing its parameters with the embed's alias and
  /// carrying its `!inner` marks one level further out.
  func merging<T>(
    _ nested: _PostgrestEmbeddedScope<T>,
    at embed: _PostgrestEmbed<T>,
    inner: Bool
  ) -> Self {
    var scope = self
    scope.items += nested.items.map {
      URLQueryItem(name: "\(embed.alias).\($0.name)", value: $0.value)
    }
    if inner {
      scope.innerEntries.append([embed.selectEntryHead])
    }
    scope.innerEntries += nested.innerEntries.map { [embed.selectEntryHead] + $0 }
    return scope
  }
}

extension _PostgrestEmbeddedScope where S: _PostgrestEmbeddingSelection {
  /// Scopes an embed nested in this one. Renders a dotted path: `comments.replies.limit=3`.
  public func embedded<T>(
    _ embed: KeyPath<S.Embeds, _PostgrestEmbed<T>>,
    _ scope: (_PostgrestEmbeddedScope<T>) -> _PostgrestEmbeddedScope<T>
  ) -> Self {
    merging(scope(_PostgrestEmbeddedScope<T>()), at: S.embeds[keyPath: embed], inner: false)
  }

  /// Scopes an embed nested in this one and drops the rows of *this* embed that have no match.
  public func requiring<T>(
    _ embed: KeyPath<S.Embeds, _PostgrestEmbed<T>>,
    _ scope: (_PostgrestEmbeddedScope<T>) -> _PostgrestEmbeddedScope<T>
  ) -> Self {
    merging(scope(_PostgrestEmbeddedScope<T>()), at: S.embeds[keyPath: embed], inner: true)
  }
}

// MARK: - Query

extension _PostgrestQuery {
  /// Shapes the rows of one embed without changing which parent rows come back.
  ///
  /// ```swift
  /// try await client.from(Todo.self)
  ///   .select(TodoWithComments.self)
  ///   .embedded(\.comments) { $0.where { $0.approved.eq(true) }.limit(5) }
  ///   .execute()
  /// // select=…,comments:comments!todo_id(…)&comments.approved=eq.true&comments.limit=5
  /// ```
  ///
  /// > Important: This is PostgREST's default, and it is a trap when the intent is "todos that
  /// > have an approved comment": every todo is returned, some with an empty `comments` array.
  /// > Use ``requiring(_:_:)`` for that.
  ///
  /// The key path names an embed of the selection, so this is available only after a selection
  /// declaring one is chosen. Call it before ``single()`` or ``maybeSingle()``.
  ///
  /// - Parameters:
  ///   - embed: The embed to scope, as `\.comments`.
  ///   - scope: Builds the filters, sort keys and row window for the embed.
  /// - Returns: A new query with the scope applied. The receiver is unchanged.
  public func embedded<S: _PostgrestEmbeddingSelection, T>(
    _ embed: KeyPath<S.Embeds, _PostgrestEmbed<T>>,
    _ scope: (_PostgrestEmbeddedScope<T>) -> _PostgrestEmbeddedScope<T>
  ) -> Self where Output == [S], S.Source == R {
    applying(_PostgrestEmbeddedScope<S>().embedded(embed, scope))
  }

  /// Shapes the rows of one embed and drops the parent rows that have no match.
  ///
  /// ```swift
  /// try await client.from(Todo.self)
  ///   .select(TodoWithComments.self)
  ///   .where { $0.isDone.eq(false) }
  ///   .requiring(\.comments) {
  ///     $0.where { $0.approved.eq(true) || $0.authorID.eq(me) }
  ///       .order { $0.createdAt.desc() }
  ///       .limit(5)
  ///   }
  ///   .execute()
  /// // select=…,comments:comments!todo_id!inner(…)&is_done=eq.false
  /// //   &comments.or=(approved.eq.true,author_id.eq.<me>)
  /// //   &comments.order=created_at.desc&comments.limit=5
  /// ```
  ///
  /// This is the `!inner` form. ``embedded(_:_:)`` is the same scope without it, which keeps
  /// every parent row. The two are separate methods, not a flag, so the choice is made at every
  /// call site — whichever default a flag chose would be silently wrong half the time.
  ///
  /// - Parameters:
  ///   - embed: The embed to scope, as `\.comments`.
  ///   - scope: Builds the filters, sort keys and row window for the embed.
  /// - Returns: A new query with the scope applied. The receiver is unchanged.
  public func requiring<S: _PostgrestEmbeddingSelection, T>(
    _ embed: KeyPath<S.Embeds, _PostgrestEmbed<T>>,
    _ scope: (_PostgrestEmbeddedScope<T>) -> _PostgrestEmbeddedScope<T>
  ) -> Self where Output == [S], S.Source == R {
    applying(_PostgrestEmbeddedScope<S>().requiring(embed, scope))
  }

  /// Appends a top-level scope's parameters and marks its `!inner` entries in `select`.
  private func applying<S>(_ scope: _PostgrestEmbeddedScope<S>) -> Self {
    var query = self
    query.request.query += scope.items
    guard
      !scope.innerEntries.isEmpty,
      let index = query.request.query.firstIndex(where: { $0.name == "select" }),
      var select = query.request.query[index].value
    else { return query }
    for entry in scope.innerEntries {
      select = Self.markingInner(entry, in: select)
    }
    query.request.query[index].value = select
    return query
  }

  /// Inserts `!inner` into the entry at `path`, a chain of select-entry heads from the top level
  /// down. Each head is searched from where the previous one matched, so a nested alias is found
  /// inside its parent's parentheses and not at an unrelated level.
  ///
  /// Hint first, then `!inner`: §9.2 verified either order is accepted, and one is pinned.
  static func markingInner(_ path: [String], in select: String) -> String {
    var select = select
    var searchStart = select.startIndex
    var alreadyInner = false
    for head in path {
      // An entry at this level is spelled one of two ways; take whichever comes first.
      let plain = select.range(of: head + "(", range: searchStart..<select.endIndex)
      let inner = select.range(of: head + "!inner(", range: searchStart..<select.endIndex)
      guard
        let found = [plain, inner].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound })
      else {
        reportIssue(
          """
          The embed `\(head)` is not in the rendered select list, so `requiring` cannot mark \
          it `!inner`: `\(select)`. Its selection's `selectString` and `embeds` disagree.
          """
        )
        return select
      }
      alreadyInner = found == inner
      searchStart = select.index(found.lowerBound, offsetBy: head.count)
    }
    if !alreadyInner {
      select.insert(contentsOf: "!inner", at: searchStart)
    }
    return select
  }
}
