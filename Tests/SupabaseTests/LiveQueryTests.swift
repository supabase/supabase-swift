//
//  LiveQueryTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 30/10/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Realtime
@_spi(Experimental) @testable import Supabase

private struct Item: Decodable, Equatable, Sendable {
  var id: Int
  var title: String
}

private typealias Machine = LiveQueryMachine<Item>

private let t0 = Date(timeIntervalSince1970: 1_793_000_000)

private func item(_ id: Int, _ title: String) -> LiveRow<Item> {
  LiveRow(key: [.integer(id)], row: Item(id: id, title: title))
}

private func change(
  _ kind: String, record: JSONObject? = nil, old: JSONObject? = nil, at offset: TimeInterval = 0
) -> PostgresChange {
  var payload: JSONObject = [
    "type": .string(kind), "schema": "public", "table": "items",
    "commit_timestamp": .string(ISO8601DateFormatter().string(from: t0 + offset)),
  ]
  payload["record"] = record.map(JSONValue.object)
  payload["old_record"] = old.map(JSONValue.object)
  return try! PostgresChange(payload: payload)
}

private func machine() -> Machine {
  Machine(primaryKey: ["id"]) { try $0.decode(as: Item.self) }
}

@Suite
struct LiveQueryMachineTests {
  @Test
  func startsWithAFetch() {
    var sut = machine()
    #expect(sut.start() == [.fetch(generation: 1)])
  }

  @Test
  func emitsTheFetchedRowsInFetchOrder() throws {
    var sut = machine()
    _ = sut.start()

    let effects = try sut.handle(.fetched(generation: 1, [item(2, "b"), item(1, "a")]))

    #expect(effects == [.emit(.rows([Item(id: 2, title: "b"), Item(id: 1, title: "a")]))])
  }

  @Test
  func appliesChangesThatArriveDuringTheFetchAfterIt() throws {
    var sut = machine()
    _ = sut.start()

    #expect(
      try sut.handle(.change(change("UPDATE", record: ["id": 1, "title": "a2"], at: 1))) == [])
    #expect(
      try sut.handle(.change(change("INSERT", record: ["id": 3, "title": "c"], at: 2))) == [])
    #expect(try sut.handle(.change(change("DELETE", old: ["id": 2], at: 3))) == [])

    let effects = try sut.handle(.fetched(generation: 1, [item(1, "a"), item(2, "b")]))

    #expect(effects == [.emit(.rows([Item(id: 1, title: "a2"), Item(id: 3, title: "c")]))])
  }

  @Test
  func appliesLiveChangesByPrimaryKey() throws {
    var sut = machine()
    _ = sut.start()
    _ = try sut.handle(.fetched(generation: 1, [item(1, "a"), item(2, "b")]))

    #expect(
      try sut.handle(.change(change("INSERT", record: ["id": 3, "title": "c"])))
        == [
          .emit(.rows([Item(id: 1, title: "a"), Item(id: 2, title: "b"), Item(id: 3, title: "c")]))
        ]
    )
    #expect(
      try sut.handle(.change(change("UPDATE", record: ["id": 1, "title": "a2"])))
        == [
          .emit(
            .rows([Item(id: 1, title: "a2"), Item(id: 2, title: "b"), Item(id: 3, title: "c")]))
        ]
    )
    #expect(
      try sut.handle(.change(change("DELETE", old: ["id": 2])))
        == [.emit(.rows([Item(id: 1, title: "a2"), Item(id: 3, title: "c")]))]
    )
  }

  @Test
  func ignoresAChangeOfAnotherKind() throws {
    var sut = machine()
    _ = sut.start()
    _ = try sut.handle(.fetched(generation: 1, [item(1, "a")]))

    #expect(try sut.handle(.change(change("TRUNCATE"))) == [])
  }

  @Test
  func ignoresADeleteOfARowItDoesNotHold() throws {
    var sut = machine()
    _ = sut.start()
    _ = try sut.handle(.fetched(generation: 1, [item(1, "a")]))

    #expect(try sut.handle(.change(change("DELETE", old: ["id": 9]))) == [])
  }

  @Test
  func skipsAChangeOlderThanTheLastOneAppliedToItsRow() throws {
    var sut = machine()
    _ = sut.start()
    _ = try sut.handle(.fetched(generation: 1, [item(1, "a")]))
    _ = try sut.handle(.change(change("UPDATE", record: ["id": 1, "title": "new"], at: 10)))

    let effects = try sut.handle(
      .change(change("UPDATE", record: ["id": 1, "title": "old"], at: 5)))

    #expect(effects == [])
  }

  @Test
  func skipsAnInsertOlderThanTheDeleteOfItsRow() throws {
    var sut = machine()
    _ = sut.start()
    _ = try sut.handle(.fetched(generation: 1, [item(1, "a")]))
    _ = try sut.handle(.change(change("DELETE", old: ["id": 1], at: 10)))

    let effects = try sut.handle(
      .change(change("UPDATE", record: ["id": 1, "title": "stale"], at: 5)))

    #expect(effects == [])
  }

  @Test
  func fetchesAgainAfterAResubscribe() throws {
    var sut = machine()
    _ = sut.start()
    _ = try sut.handle(.fetched(generation: 1, [item(1, "a")]))

    #expect(try sut.handle(.resubscribed) == [.emit(.stale), .fetch(generation: 2)])
    #expect(
      try sut.handle(.change(change("INSERT", record: ["id": 2, "title": "b"], at: 1))) == [])
    #expect(try sut.handle(.fetched(generation: 1, [item(9, "old fetch")])) == [])

    let effects = try sut.handle(.fetched(generation: 2, [item(1, "a1")]))

    #expect(effects == [.emit(.rows([Item(id: 1, title: "a1"), Item(id: 2, title: "b")]))])
  }

  @Test
  func reportsStaleWhileTheChannelIsAway() throws {
    var sut = machine()
    _ = sut.start()
    _ = try sut.handle(.fetched(generation: 1, [item(1, "a")]))

    #expect(try sut.handle(.status(.subscribing(attempt: 2))) == [.emit(.stale)])
    #expect(try sut.handle(.status(.subscribed)) == [])
  }

  @Test
  func staysStaleWhenAFetchEndsWhileTheChannelIsAway() throws {
    var sut = machine()
    _ = sut.start()

    _ = try sut.handle(
      .status(.resubscribing(attempt: 1, retryIn: .seconds(1), lastError: .decoding("x"))))
    let effects = try sut.handle(.fetched(generation: 1, [item(1, "a")]))

    #expect(effects == [.emit(.rows([Item(id: 1, title: "a")])), .emit(.stale)])
  }

  @Test
  func throwsWhenTheFetchFails() {
    var sut = machine()
    _ = sut.start()

    #expect(throws: URLError.self) {
      try sut.handle(.fetchFailed(generation: 1, URLError(.notConnectedToInternet)))
    }
  }

  @Test
  func ignoresAFailureOfAnEarlierFetch() throws {
    var sut = machine()
    _ = sut.start()
    _ = try sut.handle(.fetched(generation: 1, [item(1, "a")]))
    _ = try sut.handle(.resubscribed)

    #expect(try sut.handle(.fetchFailed(generation: 1, CancellationError())) == [])
  }

  @Test
  func throwsWhenTheChannelFails() {
    var sut = machine()
    _ = sut.start()

    #expect(throws: RealtimeError.self) {
      try sut.handle(.status(.failed(.decoding("gone"))))
    }
  }

  @Test
  func throwsWhenAChangedRowDoesNotDecode() throws {
    var sut = machine()
    _ = sut.start()
    _ = try sut.handle(.fetched(generation: 1, []))

    #expect(throws: RealtimeError.self) {
      try sut.handle(.change(change("INSERT", record: ["id": "not a number"])))
    }
  }
}

@Suite
struct LiveQueryUpdatesTests {
  private struct Fixture {
    let signals: AsyncStream<PostgresChangesSignal>
    let signal: AsyncStream<PostgresChangesSignal>.Continuation
    let finished = LockIsolated(false)

    init() {
      (signals, signal) = AsyncStream.makeStream()
    }

    func source(
      subscribe: @escaping @Sendable () async throws -> Void = {},
      fetch: @escaping @Sendable () async throws -> [LiveRow<Item>]
    ) -> LiveQuerySource<Item> {
      let finished = finished
      return LiveQuerySource(
        signals: signals,
        primaryKey: ["id"],
        decode: { try $0.decode(as: Item.self) },
        subscribe: subscribe,
        fetch: fetch,
        finish: { finished.setValue(true) }
      )
    }
  }

  @Test
  func deliversTheFetchThenLiveChanges() async throws {
    let fixture = Fixture()
    let updates = makeLiveQueryUpdates { fixture.source { [item(1, "a")] } }
    var iterator = updates.makeAsyncIterator()

    #expect(try await iterator.next() == .rows([Item(id: 1, title: "a")]))

    fixture.signal.yield(.change(change("INSERT", record: ["id": 2, "title": "b"])))
    #expect(
      try await iterator.next() == .rows([Item(id: 1, title: "a"), Item(id: 2, title: "b")]))

    fixture.signal.finish()
    #expect(try await iterator.next() == nil)
    await waitUntil { fixture.finished.value }
  }

  @Test
  func subscribesBeforeItFetches() async throws {
    let fixture = Fixture()
    let order = LockIsolated<[String]>([])
    let updates = makeLiveQueryUpdates {
      fixture.source(
        subscribe: { order.withValue { $0.append("subscribe") } },
        fetch: {
          order.withValue { $0.append("fetch") }
          return []
        }
      )
    }

    for try await _ in updates { break }

    #expect(order.value == ["subscribe", "fetch"])
  }

  @Test
  func throwsWhenTheSubscribeFails() async {
    let fixture = Fixture()
    let updates = makeLiveQueryUpdates {
      fixture.source(subscribe: { throw RealtimeError.decoding("refused") }, fetch: { [] })
    }

    await #expect(throws: RealtimeError.self) {
      for try await _ in updates {}
    }
    await waitUntil { fixture.finished.value }
  }

  @Test
  func throwsWhenTheFetchFails() async {
    let fixture = Fixture()
    let updates = makeLiveQueryUpdates { fixture.source { throw URLError(.timedOut) } }

    await #expect(throws: URLError.self) {
      for try await _ in updates {}
    }
    await waitUntil { fixture.finished.value }
  }

  @Test
  func finishesWhenTheIterationEnds() async throws {
    let fixture = Fixture()
    let task = Task {
      for try await _ in makeLiveQueryUpdates({ fixture.source { [] } }) {}
    }

    task.cancel()
    _ = await task.result

    await waitUntil { fixture.finished.value }
  }
}

/// Written out as `@Table("items")` with `@PrimaryKey var id` would expand it, for the reason
/// `RealtimeTodo` gives.
private struct LiveItem: _PostgrestKeyedRelation, Equatable {
  static let relationName = "items"
  static let selectString = "*"
  static let primaryKeyColumns = ["id"]

  var id: Int
  var title: String
  var listId: Int

  enum CodingKeys: String, CodingKey {
    case id, title
    case listId = "list_id"
  }

  struct Columns: Sendable {
    let id = _PostgrestColumn<LiveItem, Int>("id")
    let title = _PostgrestColumn<LiveItem, String>("title")
    let listId = _PostgrestColumn<LiveItem, Int>("list_id")
  }

  static let columns = Columns()
}

private func makeClient(
  respond: @escaping @Sendable (HTTPRequest) -> String = { _ in "[]" }
) -> SupabaseClient {
  SupabaseClient(
    supabaseURL: URL(string: "https://project-ref.supabase.co")!,
    supabaseKey: "PUBLISHABLE_KEY",
    options: SupabaseClientOptions(
      auth: SupabaseClientOptions.AuthOptions(
        storage: AuthLocalStorageMock(),
        autoRefresh: .manual
      ),
      global: SupabaseClientOptions.GlobalOptions(
        http: .init(
          transport: ClosureTransport { request, _ in
            (
              HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
              HTTPBody(Data(respond(request).utf8))
            )
          }
        )
      )
    )
  )
}

@Suite
struct SupabaseClientStreamTests {
  @Test
  func bindsTheFilteredRowsAndEveryDelete() async {
    let supabase = makeClient { _ in "[]" }

    let source = await supabase.liveQuerySource(
      for: LiveItem.self, filter: LiveItem.columns.listId.eq(7))
    withExtendedLifetime(source) {}

    let channels = await supabase.realtime.channels
    #expect(channels.count == 1)
    let bindings = await channels.first?.clientChanges
    #expect(
      bindings == [
        PostgresJoinConfig(event: .all, schema: "public", table: "items", filter: "list_id=eq.7"),
        PostgresJoinConfig(event: .delete, schema: "public", table: "items"),
      ]
    )

    await source.finish()
    #expect(await supabase.realtime.channels.isEmpty)
  }

  @Test
  func bindsEveryChangeWithoutAFilter() async {
    let supabase = makeClient { _ in "[]" }

    let source = await supabase.liveQuerySource(for: LiveItem.self, filter: nil)
    withExtendedLifetime(source) {}

    let bindings = await supabase.realtime.channels.first?.clientChanges
    #expect(bindings == [PostgresJoinConfig(event: .all, schema: "public", table: "items")])
    await source.finish()
  }

  @Test
  func usesADedicatedChannelPerStream() async {
    let supabase = makeClient { _ in "[]" }

    let first = await supabase.liveQuerySource(for: LiveItem.self, filter: nil)
    let second = await supabase.liveQuerySource(for: LiveItem.self, filter: nil)

    #expect(await supabase.realtime.channels.count == 2)
    await first.finish()
    await second.finish()
  }

  @Test
  func throwsWhenAFetchedRowLacksItsPrimaryKey() async throws {
    let supabase = makeClient { _ in #"[{"title":"a","list_id":7}]"# }

    let source = await supabase.liveQuerySource(for: LiveItem.self, filter: nil)
    let error = await #expect(throws: PostgrestError.self) { try await source.fetch() }
    await source.finish()

    let underlying = try #require(error?.underlyingError as? DecodingError)
    guard case .dataCorrupted(let context) = underlying else {
      Issue.record("Expected dataCorrupted, got \(underlying)")
      return
    }
    #expect(context.debugDescription.contains("primary key column `id`"))
  }

  @Test
  func streamsTheRowsOfEachUpdateAndSkipsStaleOnes() async throws {
    let (updates, update) = AsyncThrowingStream<LiveQueryUpdate<Item>, any Error>.makeStream()
    let rows = makeClient().liveRows(from: updates)

    update.yield(.stale)
    update.yield(.rows([Item(id: 1, title: "a")]))
    update.yield(.stale)
    update.yield(.rows([]))
    update.finish(throwing: URLError(.timedOut))

    var received: [[Item]] = []
    await #expect(throws: URLError.self) {
      for try await element in rows {
        received.append(element)
      }
    }
    #expect(received == [[Item(id: 1, title: "a")], []])
  }

  @Test
  func fetchesTheFilteredRowsWithTheirKeys() async throws {
    let path = LockIsolated<String?>(nil)
    let supabase = makeClient { request in
      path.setValue(request.path)
      return #"[{"id":2,"title":"b","list_id":7},{"id":1,"title":"a","list_id":7}]"#
    }

    let source = await supabase.liveQuerySource(
      for: LiveItem.self, filter: LiveItem.columns.listId.eq(7))
    let rows = try await source.fetch()
    await source.finish()

    #expect(path.value == "/rest/v1/items?select=%2A&list_id=eq.7")
    #expect(rows.map(\.key) == [[.integer(2)], [.integer(1)]])
    #expect(
      rows.map(\.row) == [
        LiveItem(id: 2, title: "b", listId: 7), LiveItem(id: 1, title: "a", listId: 7),
      ])
  }
}

@Suite
@MainActor
struct LiveQueryObservableTests {
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test
  func startsEmptyAndNotLive() {
    let sut = LiveQuery(makeClient(), LiveItem.self, where: { $0.listId.eq(7) })

    #expect(sut.rows.isEmpty)
    #expect(sut.isLive == false)
    #expect(sut.error == nil)
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test
  func publishesRowsAndLiveness() async throws {
    let (updates, update) = AsyncThrowingStream<LiveQueryUpdate<Item>, any Error>.makeStream()
    let sut = LiveQuery<Item> { updates }

    let run = Task { await sut.run() }
    #expect(sut.isLive == false)

    update.yield(.rows([Item(id: 1, title: "a")]))
    await waitUntil { await sut.rows == [Item(id: 1, title: "a")] }
    #expect(sut.isLive)

    update.yield(.stale)
    await waitUntil { await !sut.isLive }
    #expect(sut.rows == [Item(id: 1, title: "a")])

    update.finish(throwing: URLError(.timedOut))
    await run.value
    #expect(sut.error is URLError)
    #expect(sut.isLive == false)
  }
}
