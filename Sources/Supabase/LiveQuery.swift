//
//  LiveQuery.swift
//  Supabase
//
//  Created by Guilherme Souza on 30/10/26.
//

#if canImport(Observation)
  public import Observation
  public import PostgREST

  #if canImport(SwiftUI)
    public import SwiftUI
  #endif

  /// The rows of a relation, kept in sync with the database, as observable state.
  ///
  /// It runs the same live query as ``SupabaseClient/stream(_:where:)`` and publishes the result
  /// on the main actor. Nothing starts until you call ``run()``. In SwiftUI, call it from the
  /// `task` modifier, so the query ends when the view goes away:
  ///
  /// ```swift
  /// struct TodoList: View {
  ///   @State private var todos = LiveQuery(supabase, Todo.self, where: { $0.isDone.eq(false) })
  ///
  ///   var body: some View {
  ///     List(todos.rows, id: \.id) { todo in
  ///       Text(todo.title)
  ///     }
  ///     .task { await todos.run() }
  ///   }
  /// }
  /// ```
  ///
  /// Pass an `animation` to animate the changes to ``rows``, the way SwiftData's `@Query` does:
  ///
  /// ```swift
  /// @State private var todos = LiveQuery(supabase, Todo.self, animation: .default)
  /// ```
  ///
  /// > Warning: The typed query API is experimental. Its shape may change in a minor release.
  /// > Opt in with `@_spi(Experimental) import Supabase`.
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @_spi(Experimental)
  @MainActor
  @Observable
  public final class LiveQuery<R: Sendable> {
    /// The current rows. They keep their values while the query is not live.
    public private(set) var rows: [R] = []

    /// Whether ``rows`` are in sync with the database. It is `false` before the first fetch
    /// completes, while the channel is away, while the query fetches again after the channel
    /// joins again, and after ``run()`` returns.
    public private(set) var isLive = false

    /// The error that ended the last ``run()``, or `nil`.
    public private(set) var error: (any Error)?

    #if canImport(SwiftUI)
      /// The animation for changes to ``rows``, or `nil` to change them without one.
      ///
      /// Only ``rows`` animate. ``isLive`` and ``error`` change without an animation.
      @ObservationIgnored
      public var animation: Animation?
    #endif

    @ObservationIgnored
    private let makeUpdates: @Sendable () -> AsyncThrowingStream<LiveQueryUpdate<R>, any Error>

    init(
      makeUpdates: @escaping @Sendable () -> AsyncThrowingStream<LiveQueryUpdate<R>, any Error>
    ) {
      self.makeUpdates = makeUpdates
    }

    /// Runs the query until the calling task is cancelled or the query fails.
    ///
    /// The method opens a channel of its own and removes it before it returns. When the query
    /// fails, the method sets ``error`` and returns. Call it again to start over. Do not run it
    /// twice at the same time.
    public func run() async {
      error = nil
      do {
        for try await update in makeUpdates() {
          switch update {
          case .rows(let rows):
            publish(rows)
            isLive = true
          case .stale:
            isLive = false
          }
        }
      } catch {
        self.error = error
      }
      isLive = false
    }

    private func publish(_ rows: [R]) {
      #if canImport(SwiftUI)
        if let animation {
          withAnimation(animation) { self.rows = rows }
          return
        }
      #endif
      self.rows = rows
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension LiveQuery where R: _PostgrestKeyedRelation {
    /// Creates a live query for the rows of a relation.
    ///
    /// The filter takes only what Realtime can run. See ``SupabaseClient/stream(_:where:)`` for
    /// the operators, and for how the rows stay in sync.
    ///
    /// - Parameters:
    ///   - client: The client to fetch and subscribe with.
    ///   - relation: The relation to read. It needs a primary key, so changes can be matched to
    ///     rows.
    ///   - filter: Builds the filter from the relation's columns, or `nil` for every row.
    public convenience init(
      _ client: SupabaseClient,
      _ relation: R.Type = R.self,
      where filter: ((R.Columns) -> _PostgrestFilter<R>)? = nil
    ) {
      let filter = filter?(R.columns)
      self.init { client.liveQueryUpdates(R.self, filter: filter) }
    }

    #if canImport(SwiftUI)
      /// Creates a live query for the rows of a relation that animates the changes to its rows.
      ///
      /// - Parameters:
      ///   - client: The client to fetch and subscribe with.
      ///   - relation: The relation to read. It needs a primary key, so changes can be matched to
      ///     rows.
      ///   - filter: Builds the filter from the relation's columns, or `nil` for every row.
      ///   - animation: The animation for changes to ``LiveQuery/rows``, or `nil` for none.
      public convenience init(
        _ client: SupabaseClient,
        _ relation: R.Type = R.self,
        where filter: ((R.Columns) -> _PostgrestFilter<R>)? = nil,
        animation: Animation?
      ) {
        self.init(client, relation, where: filter)
        self.animation = animation
      }
    #endif
  }
#endif
