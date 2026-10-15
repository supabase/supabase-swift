//
//  PostgrestRpcTests.swift
//  Supabase
//
//  Created by Lukas Klingsbo on 15/10/26.
//

import Foundation
import Testing

@_spi(Experimental) @testable import PostgREST

@Suite
struct PostgrestRpcTests {
  struct Book: _PostgrestRelation {
    static let relationName = "books"
    static let selectString = "*"

    var id: Int
    var title: String

    struct Columns: Sendable {
      let id = _PostgrestColumn<Book, Int>("id")
      let title = _PostgrestColumn<Book, String>("title")
    }

    static let columns = Columns()
  }

  enum Inventory: _PostgrestSchema {
    static let name = "inventory"
  }

  @Test
  func rowsSendsTheArgumentsAsTheBody() async throws {
    let capture = QueryCapture(body: #"[{"id":1,"title":"Dune"}]"#)

    let books: [Book] = try await capture.client.rpc
      .rows("search_books", arguments: ["query": "dune"])
      .execute()
      .value

    #expect(books.map(\.title) == ["Dune"])
    #expect(capture.httpMethod == "POST")
    #expect(capture.path == "/rpc/search_books")
    #expect(capture.bodyString == #"{"query":"dune"}"#)
    #expect(capture.query == nil)
  }

  @Test
  func rowsFiltersSortsAndLimitsTheResult() async throws {
    let capture = QueryCapture()

    let query: _PostgrestQuery<Book, [Book]> = try capture.client.rpc.rows("search_books")
    _ = try await query.where { $0.id.gt(1) }.order { $0.title.desc() }.limit(5).execute()

    #expect(capture.query == "id=gt.1&order=title.desc&limit=5")
    #expect(capture.bodyString == nil)
  }

  @Test
  func rowsReadsASingleRow() async throws {
    let capture = QueryCapture(body: #"{"id":1,"title":"Dune"}"#)

    let query: _PostgrestQuery<Book, [Book]> = try capture.client.rpc.rows("search_books")
    let book = try await query.single().execute().value

    #expect(book.id == 1)
    #expect(capture.header("Accept") == "application/vnd.pgrst.object+json")
  }

  @Test
  func aNilArgumentIsLeftOut() async throws {
    let capture = QueryCapture()
    let maxPrice: Int? = nil

    let query: _PostgrestQuery<Book, [Book]> = try capture.client.rpc.rows(
      "search_books", arguments: ["query": "dune", "max_price": maxPrice])
    _ = try await query.execute()

    #expect(capture.bodyString == #"{"query":"dune"}"#)
  }

  @Test
  func countCallsTheFunctionWithItsArgumentsAndAsksForNoRows() async throws {
    let capture = QueryCapture(body: "[]", responseHeaders: ["Content-Range": "*/2"])

    let query: _PostgrestQuery<Book, [Book]> = try capture.client.rpc.rows(
      "search_books", arguments: ["query": "dune"])
    let count = try await query.where { $0.id.gt(1) }.limit(5).count(.exact)

    #expect(count == 2)
    #expect(capture.httpMethod == "POST")
    #expect(capture.query == "id=gt.1&limit=0")
    #expect(capture.bodyString == #"{"query":"dune"}"#)
    #expect(capture.header("Prefer") == "count=exact")
  }

  @Test
  func datesAndDecimalsAreSentTheWayPostgresReadsThem() async throws {
    let capture = QueryCapture()
    let since: Date? = Date(timeIntervalSince1970: 0)

    let query: _PostgrestQuery<Book, [Book]> = try capture.client.rpc.rows(
      "search_books", arguments: ["since": since, "max_price": Decimal(string: "1.5")!])
    _ = try await query.execute()

    let body = try JSONDecoder().decode(
      [String: JSONValue].self, from: Data(try #require(capture.bodyString).utf8))
    #expect(body["max_price"] == 1.5)
    #expect(body["since"]?.stringValue?.hasPrefix("1970-01-01T00:00:00") == true)
  }

  @Test
  func rowDecodesTheReturnedRow() async throws {
    let capture = QueryCapture(body: #"{"id":1,"title":"Dune"}"#)

    let book: Book? = try await capture.client.rpc
      .row("book_by_id", arguments: ["book_id": 1])
      .execute()
      .value

    #expect(book?.title == "Dune")
  }

  @Test(arguments: [#"{"id":null,"title":null}"#, "null"])
  func rowDecodesNoRowAsNil(body: String) async throws {
    let capture = QueryCapture(body: body)

    let book: Book? = try await capture.client.rpc
      .row("book_by_id", arguments: ["book_id": 1])
      .execute()
      .value

    #expect(book == nil)
  }

  @Test
  func valueDecodesAScalar() async throws {
    let capture = QueryCapture(body: "3")

    let count: Int? = try await capture.client.rpc.value("count_books").execute().value

    #expect(count == 3)
    #expect(capture.path == "/rpc/count_books")
    #expect(capture.bodyString == nil)
  }

  @Test
  func valueDecodesASetOfScalars() async throws {
    let capture = QueryCapture(body: "[1,null,3]")

    let ids: [Int?] = try await capture.client.rpc.value("book_ids").execute().value

    #expect(ids == [1, nil, 3])
  }

  @Test
  func valueSendsAWholeBody() async throws {
    let capture = QueryCapture(body: #"{"a":1}"#)

    let echoed: JSONValue? = try await capture.client.rpc
      .value("echo", arguments: _PostgrestArguments(JSONValue.object(["a": .integer(1)])))
      .execute()
      .value

    #expect(echoed == .object(["a": .integer(1)]))
    #expect(capture.bodyString == #"{"a":1}"#)
  }

  @Test
  func performIgnoresTheResponseBody() async throws {
    let capture = QueryCapture(body: "")

    try await capture.client.rpc.perform("touch_book", arguments: ["book_id": 1]).execute()

    #expect(capture.httpMethod == "POST")
    #expect(capture.bodyString == #"{"book_id":1}"#)
  }

  @Test
  func callsInTheSchemaItIsGiven() async throws {
    let capture = QueryCapture(body: "null")

    try await capture.client.rpc.perform("restock", schema: Inventory.self).execute()

    #expect(capture.header("Content-Profile") == "inventory")
  }

  @Test
  func callsInTheSchemaTheClientWasScopedToOverTheOneItIsGiven() async throws {
    let capture = QueryCapture(body: "null")

    try await capture.client.schema("archive").rpc.perform("restock", schema: Inventory.self)
      .execute()

    #expect(capture.header("Content-Profile") == "archive")
  }

  @Test
  func theUntypedCallStillCompiles() async throws {
    let capture = QueryCapture(body: "3")

    let count: Int = try await capture.client.rpc("count_books").execute().value

    #expect(count == 3)
  }
}
