//
//  QueryEncodingTests.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 22/08/26.
//

import Foundation
import Testing

@testable import HTTPRuntime

@Suite
struct QueryEncodingTests {
  let baseURL = URL(string: "https://example.supabase.co")!

  // MARK: - Encoding

  @Test
  func escapesPlusSoAFormDecodingServerCannotReadItAsASpace() {
    // The reason this type exists. `URLComponents.queryItems` leaves both of these literal.
    #expect(QueryEncoding.item("eq.+16505555555") == "eq.%2B16505555555")
    #expect(
      QueryEncoding.item("gt.2023-03-23T15:50:30.511743+00:00")
        == "gt.2023-03-23T15%3A50%3A30.511743%2B00%3A00")
  }

  @Test
  func escapesEveryDelimiterThatWouldOtherwiseEndTheItem() {
    // `&` and `=` would end the parameter early and `%` would start an escape sequence. All three
    // are values a caller can legitimately pass — a `like` pattern uses `%`.
    #expect(QueryEncoding.item("eq.a&b=c%d") == "eq.a%26b%3Dc%25d")
  }

  @Test
  func leavesSlashAndQuestionMarkAlone() {
    // RFC 3986 section 3.4 allows both inside a query. Escaping them would make a URL passed as a
    // parameter value unreadable in a log for no gain.
    #expect(QueryEncoding.item("eq.https://example.com/a?b") == "eq.https%3A//example.com/a?b")
  }

  @Test
  func rendersNothingForNoItems() {
    #expect(QueryEncoding.render([]) == nil)
  }

  @Test
  func rendersAValuelessItemWithoutAnEqualsSign() {
    #expect(QueryEncoding.render([URLQueryItem(name: "columns", value: nil)]) == "columns")
  }

  @Test
  func rendersNamesAsWellAsValues() {
    // An embedded-resource filter puts a dot-qualified name on the left of the `=`, and a column
    // name is caller data just as much as a value is.
    let rendered = QueryEncoding.render([URLQueryItem(name: "a b&c", value: "eq.1")])

    #expect(rendered == "a%20b%26c=eq.1")
  }

  // MARK: - The builder

  @Test
  func repeatedNamesBothSurvive() throws {
    // Repeated-key encoding is the documented contract of `addQuery`, and PostgREST ANDs repeated
    // keys — `.gt(\.id, 1).lt(\.id, 9)` needs both halves to arrive.
    var builder = HTTPRequestBuilder(method: .get, baseURL: baseURL, path: "/todos")
    builder.addQuery("id", "gt.1")
    builder.addQuery("id", "lt.9")

    let request = try builder.build()

    #expect(request.url.absoluteString == "https://example.supabase.co/todos?id=gt.1&id=lt.9")
  }

  @Test
  func itemsKeepInsertionOrder() throws {
    var builder = HTTPRequestBuilder(method: .get, baseURL: baseURL, path: "/todos")
    builder.addQuery("select", "*")
    builder.addQuery("done", "eq.false")

    let request = try builder.build()

    #expect(
      request.url.absoluteString == "https://example.supabase.co/todos?select=%2A&done=eq.false")
  }

  @Test
  func noQueryItemsLeavesNoQuestionMark() throws {
    let builder = HTTPRequestBuilder(method: .get, baseURL: baseURL, path: "/todos")

    let request = try builder.build()

    #expect(request.url.absoluteString == "https://example.supabase.co/todos")
  }

  @Test
  func aNilValueIsSkipped() throws {
    var builder = HTTPRequestBuilder(method: .get, baseURL: baseURL, path: "/todos")
    builder.addQuery("select", "*")
    builder.addQuery("done", String?.none)

    let request = try builder.build()

    #expect(request.url.absoluteString == "https://example.supabase.co/todos?select=%2A")
  }

  @Test
  func aValueIsNotEncodedTwice() throws {
    // Items are stored unescaped and encoded once, at build time. Encoding on the way in would
    // turn the `%` of an existing escape sequence into `%25`.
    var builder = HTTPRequestBuilder(method: .get, baseURL: baseURL, path: "/todos")
    builder.addQuery("col", "eq.100%")

    let request = try builder.build()

    #expect(request.url.absoluteString == "https://example.supabase.co/todos?col=eq.100%25")
  }

  @Test
  func setQueryReplacesInPlaceRatherThanMovingToTheEnd() throws {
    var builder = HTTPRequestBuilder(method: .get, baseURL: baseURL, path: "/todos")
    builder.setQuery("select", "*")
    builder.addQuery("done", "eq.false")
    builder.setQuery("select", "id,title")

    let request = try builder.build()

    #expect(
      request.url.absoluteString
        == "https://example.supabase.co/todos?select=id%2Ctitle&done=eq.false")
  }

  @Test
  func setQueryAppendsWhenAbsent() throws {
    var builder = HTTPRequestBuilder(method: .get, baseURL: baseURL, path: "/todos")
    builder.addQuery("done", "eq.false")
    builder.setQuery("select", "*")

    let request = try builder.build()

    #expect(
      request.url.absoluteString == "https://example.supabase.co/todos?done=eq.false&select=%2A")
  }

  @Test
  func setQueryReplacesOnlyTheFirstOfARepeatedName() throws {
    // A repeated name is a list or, in PostgREST's case, a conjunction on one column. Replacing
    // every match would silently turn `id=gt.1&id=lt.9` into a single condition.
    var builder = HTTPRequestBuilder(method: .get, baseURL: baseURL, path: "/todos")
    builder.addQuery("id", "gt.1")
    builder.addQuery("id", "lt.9")
    builder.setQuery("id", "eq.5")

    let request = try builder.build()

    #expect(request.url.absoluteString == "https://example.supabase.co/todos?id=eq.5&id=lt.9")
  }

  @Test
  func setQueryIgnoresNilValue() throws {
    // Matches `addQuery`, so the same argument behaves the same way in both. It sets a value; it
    // does not remove one.
    var builder = HTTPRequestBuilder(method: .get, baseURL: baseURL, path: "/todos")
    builder.setQuery("select", "*")
    builder.setQuery("select", String?.none)

    let request = try builder.build()

    #expect(request.url.absoluteString == "https://example.supabase.co/todos?select=%2A")
  }

  // MARK: - PostgREST's recorded wire format

  @Test
  func everySingleValueOperatorEscapesItsValueTheSameWay() throws {
    // PostgREST's `test all filters and count` snapshot, which is really 25 repeats of one column
    // name. It proves repeated keys survive at scale and that the space in `Some value` is escaped
    // identically for every operator.
    let operators = [
      "eq", "neq", "gt", "gte", "lt", "lte", "like", "ilike", "match", "imatch", "is",
      "isdistinct", "in", "cs", "cd", "sl", "sr", "nxl", "nxr", "adj", "ov", "fts", "plfts",
      "phfts", "wfts",
    ]

    var builder = HTTPRequestBuilder(method: .get, baseURL: baseURL, path: "/todos")
    builder.addQuery("select", "*")
    for op in operators {
      builder.addQuery("column", "\(op).Some value")
    }

    let request = try builder.build()

    let expected =
      "https://example.supabase.co/todos?select=%2A&"
      + operators.map { "column=\($0).Some%20value" }.joined(separator: "&")
    #expect(request.url.absoluteString == expected)
  }

  struct WireFormatCase: Sendable, CustomStringConvertible {
    let name: String
    let method: HTTPMethod
    let path: String
    let queryItems: [(name: String, value: String)]
    let url: String

    var description: String { name }
  }

  /// 30 of the 32 requests PostgREST records under
  /// `Tests/PostgRESTTests/__Snapshots__/BuildURLRequestTests/`, re-expressed against
  /// `HTTPRequestBuilder`. PostgREST is `HTTPRuntime`'s first production consumer, and these are
  /// the most varied real query values in the repository — JSON objects, range literals, `like`
  /// patterns, a timestamptz offset, a non-ASCII string, a leading `+`.
  ///
  /// The expected strings are **not** copied from those snapshot files. Those are written by
  /// swift-snapshot-testing's `.curl` strategy, which sorts the query items by name and re-encodes
  /// them through `URLComponents.queryItems` — so `select=%2A` is recorded as `select=*` and
  /// insertion order is lost. Each string below is the real `URLRequest.url` the legacy PostgREST
  /// builder produces, captured by running the same 32 builder chains through a fetch handler that
  /// prints it. Matching them means this encoding puts the same bytes on the wire as the API being
  /// deprecated.
  ///
  /// The two left out have their own tests: the 25-operator case above, and `rpc call with get and
  /// params`, whose legacy order is nondeterministic — `PostgrestClient.rpc(_:params:get:)`
  /// iterates a `JSONValue` object, so it emits `index=2&array=…` on one run and `array=…&index=2`
  /// on the next. Two captures of the same chain disagreed. The snapshot never caught it because
  /// `.curl` sorts before recording. Parameter order does not change what PostgREST returns, so it
  /// is not a wire bug, but it does make the request unreproducible in a log or a cache key, and
  /// whoever rebuilds `rpc` on this builder has to choose an order.
  static let wireFormatCases: [WireFormatCase] = [
    .init(
      name: "select all users where email ends with '@supabase.co'",
      method: .get,
      path: "/users",
      queryItems: [("select", "*"), ("email", "like.%@supabase.co")],
      url: "https://example.supabase.co/users?select=%2A&email=like.%25%40supabase.co"
    ),
    .init(
      name: "insert new user",
      method: .post,
      path: "/users",
      queryItems: [],
      url: "https://example.supabase.co/users"
    ),
    .init(
      name: "bulk insert users",
      method: .post,
      path: "/users",
      queryItems: [("columns", "\"email\",\"username\"")],
      url: "https://example.supabase.co/users?columns=%22email%22%2C%22username%22"
    ),
    .init(
      name: "call rpc",
      method: .post,
      path: "/rpc/test_fcn",
      queryItems: [],
      url: "https://example.supabase.co/rpc/test_fcn"
    ),
    .init(
      name: "call rpc without parameter",
      method: .post,
      path: "/rpc/test_fcn",
      queryItems: [],
      url: "https://example.supabase.co/rpc/test_fcn"
    ),
    .init(
      name: "call rpc with filter",
      method: .post,
      path: "/rpc/test_fcn",
      queryItems: [("id", "eq.1")],
      url: "https://example.supabase.co/rpc/test_fcn?id=eq.1"
    ),
    .init(
      name: "test in filter",
      method: .get,
      path: "/todos",
      queryItems: [("select", "*"), ("id", "in.(1,2,3)")],
      url: "https://example.supabase.co/todos?select=%2A&id=in.%281%2C2%2C3%29"
    ),
    .init(
      name: "test contains filter with dictionary",
      method: .get,
      path: "/users",
      queryItems: [("select", "name"), ("address", "cs.{\"postcode\":90210}")],
      url: "https://example.supabase.co/users?select=name&address=cs.%7B%22postcode%22%3A90210%7D"
    ),
    .init(
      name: "test contains filter with array",
      method: .get,
      path: "/users",
      queryItems: [("select", "*"), ("name", "cs.{is:online,faction:red}")],
      url: "https://example.supabase.co/users?select=%2A&name=cs.%7Bis%3Aonline%2Cfaction%3Ared%7D"
    ),
    .init(
      name: "test or filter with referenced table",
      method: .get,
      path: "/users",
      queryItems: [
        ("select", "*,messages(*)"), ("messages.or", "(public.eq.true,recipient_id.eq.1)"),
      ],
      url:
        "https://example.supabase.co/users?select=%2A%2Cmessages%28%2A%29&messages.or=%28public.eq.true%2Crecipient_id.eq.1%29"
    ),
    .init(
      name: "test upsert not ignoring duplicates",
      method: .post,
      path: "/users",
      queryItems: [],
      url: "https://example.supabase.co/users"
    ),
    .init(
      name: "bulk upsert",
      method: .post,
      path: "/users",
      queryItems: [("columns", "\"email\",\"username\"")],
      url: "https://example.supabase.co/users?columns=%22email%22%2C%22username%22"
    ),
    .init(
      name: "select after bulk upsert",
      method: .post,
      path: "/users",
      queryItems: [("on_conflict", "username"), ("columns", "\"email\""), ("select", "*")],
      url: "https://example.supabase.co/users?on_conflict=username&columns=%22email%22&select=%2A"
    ),
    .init(
      name: "test upsert ignoring duplicates",
      method: .post,
      path: "/users",
      queryItems: [],
      url: "https://example.supabase.co/users"
    ),
    .init(
      name: "query with + character",
      method: .get,
      path: "/users",
      queryItems: [("select", "*"), ("id", "eq.Cigányka-ér (0+400 cskm) vízrajzi állomás")],
      url:
        "https://example.supabase.co/users?select=%2A&id=eq.Cig%C3%A1nyka-%C3%A9r%20%280%2B400%20cskm%29%20v%C3%ADzrajzi%20%C3%A1llom%C3%A1s"
    ),
    .init(
      name: "query with timestamptz",
      method: .get,
      path: "/tasks",
      queryItems: [
        ("select", "*"), ("received_at", "gt.2023-03-23T15:50:30.511743+00:00"),
        ("order", "received_at.asc.nullslast"),
      ],
      url:
        "https://example.supabase.co/tasks?select=%2A&received_at=gt.2023-03-23T15%3A50%3A30.511743%2B00%3A00&order=received_at.asc.nullslast"
    ),
    .init(
      name: "query non-default schema",
      method: .get,
      path: "/objects",
      queryItems: [("select", "*")],
      url: "https://example.supabase.co/objects?select=%2A"
    ),
    .init(
      name: "select after an insert",
      method: .post,
      path: "/users",
      queryItems: [("select", "id,email")],
      url: "https://example.supabase.co/users?select=id%2Cemail"
    ),
    .init(
      name: "query if nil value",
      method: .get,
      path: "/users",
      queryItems: [("select", "*"), ("email", "is.NULL")],
      url: "https://example.supabase.co/users?select=%2A&email=is.NULL"
    ),
    .init(
      name: "likeAllOf",
      method: .get,
      path: "/users",
      queryItems: [("select", "*"), ("email", "like(all).{%@supabase.io,%@supabase.com}")],
      url:
        "https://example.supabase.co/users?select=%2A&email=like%28all%29.%7B%25%40supabase.io%2C%25%40supabase.com%7D"
    ),
    .init(
      name: "likeAnyOf",
      method: .get,
      path: "/users",
      queryItems: [("select", "*"), ("email", "like(any).{%@supabase.io,%@supabase.com}")],
      url:
        "https://example.supabase.co/users?select=%2A&email=like%28any%29.%7B%25%40supabase.io%2C%25%40supabase.com%7D"
    ),
    .init(
      name: "iLikeAllOf",
      method: .get,
      path: "/users",
      queryItems: [("select", "*"), ("email", "ilike(all).{%@supabase.io,%@supabase.com}")],
      url:
        "https://example.supabase.co/users?select=%2A&email=ilike%28all%29.%7B%25%40supabase.io%2C%25%40supabase.com%7D"
    ),
    .init(
      name: "iLikeAnyOf",
      method: .get,
      path: "/users",
      queryItems: [("select", "*"), ("email", "ilike(any).{%@supabase.io,%@supabase.com}")],
      url:
        "https://example.supabase.co/users?select=%2A&email=ilike%28any%29.%7B%25%40supabase.io%2C%25%40supabase.com%7D"
    ),
    .init(
      name: "containedBy using array",
      method: .get,
      path: "/users",
      queryItems: [("select", "*"), ("id", "cd.{a,b,c}")],
      url: "https://example.supabase.co/users?select=%2A&id=cd.%7Ba%2Cb%2Cc%7D"
    ),
    .init(
      name: "containedBy using range",
      method: .get,
      path: "/users",
      queryItems: [("select", "*"), ("age", "cd.[10,20]")],
      url: "https://example.supabase.co/users?select=%2A&age=cd.%5B10%2C20%5D"
    ),
    .init(
      name: "containedBy using json",
      method: .get,
      path: "/users",
      queryItems: [("select", "*"), ("userMetadata", "cd.{\"age\":18}")],
      url: "https://example.supabase.co/users?select=%2A&userMetadata=cd.%7B%22age%22%3A18%7D"
    ),
    .init(
      name: "filter starting with non-alphanumeric",
      method: .get,
      path: "/users",
      queryItems: [("select", "*"), ("to", "eq.+16505555555")],
      url: "https://example.supabase.co/users?select=%2A&to=eq.%2B16505555555"
    ),
    .init(
      name: "filter using Date",
      method: .get,
      path: "/users",
      queryItems: [("select", "*"), ("created_at", "gt.1970-01-01T00:00:00.000Z")],
      url: "https://example.supabase.co/users?select=%2A&created_at=gt.1970-01-01T00%3A00%3A00.000Z"
    ),
    .init(
      name: "rpc call with head",
      method: .head,
      path: "/rpc/sum",
      queryItems: [],
      url: "https://example.supabase.co/rpc/sum"
    ),
    .init(
      name: "rpc call with get",
      method: .get,
      path: "/rpc/sum",
      queryItems: [],
      url: "https://example.supabase.co/rpc/sum"
    ),
  ]

  @Test(arguments: wireFormatCases)
  func matchesTheRecordedPostgrestWireFormat(_ testCase: WireFormatCase) throws {
    var builder = HTTPRequestBuilder(
      method: testCase.method, baseURL: baseURL, path: testCase.path)
    for item in testCase.queryItems {
      builder.addQuery(item.name, item.value)
    }

    let request = try builder.build()

    #expect(request.url.absoluteString == testCase.url)
    #expect(request.method == testCase.method)
  }
}
