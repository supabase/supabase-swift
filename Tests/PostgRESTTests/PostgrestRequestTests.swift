//
//  PostgrestRequestTests.swift
//  PostgREST
//
//  Created by Guilherme Souza on 22/08/26.
//

import Foundation
import HTTPTypes
import Testing

@testable import PostgREST

@Suite
struct PostgrestRequestTests {
  let baseURL = URL(string: "https://example.supabase.co")!

  // MARK: - Query items

  @Test
  func rendersQueryItemsInInsertionOrder() {
    var request = PostgrestRequest(method: .get, path: "/todos")
    request.appendQueryItem(name: "select", value: "*")
    request.appendQueryItem(name: "done", value: "eq.false")

    #expect(request.renderedQuery == "select=%2A&done=eq.false")
  }

  @Test
  func repeatedFilterKeysAreBothKept() {
    // PostgREST ANDs repeated keys, so `.gt(\.id, 1).lt(\.id, 9)` needs both parameters to
    // survive. A dictionary would silently drop one.
    var request = PostgrestRequest(method: .get, path: "/todos")
    request.appendQueryItem(name: "id", value: "gt.1")
    request.appendQueryItem(name: "id", value: "lt.9")

    #expect(request.renderedQuery == "id=gt.1&id=lt.9")
    #expect(request.queryValues(for: "id") == ["gt.1", "lt.9"])
  }

  @Test
  func setQueryItemReplacesInPlaceRatherThanMovingToTheEnd() {
    // `select`, `order` and `on_conflict` are read once by PostgREST, so setting one twice must
    // not leave two behind — and must not reorder the parameters around it either.
    var request = PostgrestRequest(method: .get, path: "/todos")
    request.setQueryItem(name: "select", value: "*")
    request.appendQueryItem(name: "done", value: "eq.false")
    request.setQueryItem(name: "select", value: "id,title")

    #expect(request.renderedQuery == "select=id%2Ctitle&done=eq.false")
  }

  @Test
  func setQueryItemReplacesOnlyTheFirstOfARepeatedName() {
    // A filter column can legitimately repeat. If `setQueryItem` ever needs to touch one, it
    // must not collapse the conjunction into a single parameter.
    var request = PostgrestRequest(method: .get, path: "/todos")
    request.appendQueryItem(name: "id", value: "gt.1")
    request.appendQueryItem(name: "id", value: "lt.9")
    request.setQueryItem(name: "id", value: "eq.5")

    #expect(request.renderedQuery == "id=eq.5&id=lt.9")
  }

  @Test
  func aValuelessQueryItemRendersWithoutAnEqualsSign() {
    var request = PostgrestRequest(method: .get, path: "/todos")
    request.appendQueryItem(name: "columns")

    #expect(request.renderedQuery == "columns")
  }

  @Test
  func noQueryItemsRendersAnEmptyQueryAndNoQuestionMark() {
    let request = PostgrestRequest(method: .get, path: "/todos")

    #expect(request.renderedQuery.isEmpty)
    #expect(request.renderedPath() == "/todos")
  }

  // MARK: - Escaping

  @Test
  func escapesEveryDelimiterThatWouldOtherwiseEndTheParameter() {
    // `&` and `=` would end the parameter early; `+` decodes to a space on a server that reads
    // the query as a form body; `%` would start an escape sequence. All four are real values a
    // caller can pass — `like` patterns use `%`, and phone numbers start with `+`.
    var request = PostgrestRequest(method: .get, path: "/t")
    request.appendQueryItem(name: "col", value: "eq.a&b=c+d%e")

    #expect(request.renderedQuery == "col=eq.a%26b%3Dc%2Bd%25e")
  }

  @Test
  func escapesTheNameAsWellAsTheValue() {
    // Embedded-resource filters put a dot-qualified name on the left of the `=`, and a column
    // name is user data just as much as a value is.
    var request = PostgrestRequest(method: .get, path: "/t")
    request.appendQueryItem(name: "a b&c", value: "eq.1")

    #expect(request.renderedQuery == "a%20b%26c=eq.1")
  }

  @Test
  func leavesSlashAndQuestionMarkAlone() {
    // RFC 3986 section 3.4 allows both inside a query. Escaping them would make a URL passed as a
    // filter value unreadable in logs for no gain.
    var request = PostgrestRequest(method: .get, path: "/t")
    request.appendQueryItem(name: "col", value: "eq.https://example.com/a?b")

    #expect(request.renderedQuery == "col=eq.https%3A//example.com/a?b")
  }

  @Test
  func storesValuesUnescapedSoNothingIsEncodedTwice() {
    // The value is kept exactly as given. If `appendQueryItem` escaped eagerly, rendering would
    // escape the `%` of an existing escape sequence and `%25` would become `%2525`.
    var request = PostgrestRequest(method: .get, path: "/t")
    request.appendQueryItem(name: "col", value: "eq.100%")

    #expect(request.queryItems == [.init(name: "col", value: "eq.100%")])
    #expect(request.renderedQuery == "col=eq.100%25")
  }

  // MARK: - Rendering against a base URL

  @Test
  func httpRequestCarriesMethodPathAndHeaderFields() {
    var request = PostgrestRequest(
      method: .get,
      path: "/todos",
      headerFields: [.accept: "application/json"]
    )
    request.appendQueryItem(name: "select", value: "*")

    let httpRequest = request.httpRequest(baseURL: baseURL)

    #expect(httpRequest.method == .get)
    #expect(httpRequest.scheme == "https")
    #expect(httpRequest.authority == "example.supabase.co")
    #expect(httpRequest.path == "/todos?select=%2A")
    #expect(httpRequest.headerFields[.accept] == "application/json")
  }

  @Test
  func httpRequestKeepsTheBaseURLsOwnPathAsAPrefix() {
    // A Supabase project's PostgREST lives under `/rest/v1`, so dropping the base path would
    // send every request to the wrong place.
    var request = PostgrestRequest(method: .get, path: "/todos")
    request.appendQueryItem(name: "select", value: "*")

    let httpRequest = request.httpRequest(
      baseURL: URL(string: "https://project.supabase.co/rest/v1")!)

    #expect(httpRequest.path == "/rest/v1/todos?select=%2A")
  }

  @Test
  func httpRequestKeepsAnExplicitPort() {
    let request = PostgrestRequest(method: .get, path: "/todos")

    let httpRequest = request.httpRequest(baseURL: URL(string: "http://localhost:54321/rest/v1")!)

    #expect(httpRequest.authority == "localhost:54321")
    #expect(httpRequest.path == "/rest/v1/todos")
  }

  @Test
  func bodyIsCarriedVerbatimAndIsNotPartOfTheRenderedPath() {
    let body = Data(#"{"email":"johndoe@supabase.io"}"#.utf8)
    let request = PostgrestRequest(method: .post, path: "/users", body: body)

    #expect(request.body == body)
    #expect(request.renderedPath() == "/users")
  }

  // MARK: - The legacy wire format

  @Test
  func everySingleValueOperatorEscapesItsValueTheSameWay() {
    // The legacy `test all filters and count` snapshot, which is really 25 repeats of one column
    // name. It is the case that proves repeated keys survive at scale, and that the space in
    // `Some value` is escaped identically for every operator.
    let operators = [
      "eq", "neq", "gt", "gte", "lt", "lte", "like", "ilike", "match", "imatch", "is",
      "isdistinct", "in", "cs", "cd", "sl", "sr", "nxl", "nxr", "adj", "ov", "fts", "plfts",
      "phfts", "wfts",
    ]

    var request = PostgrestRequest(method: .get, path: "/todos")
    request.setQueryItem(name: "select", value: "*")
    for op in operators {
      request.appendQueryItem(name: "column", value: "\(op).Some value")
    }

    let expected =
      "/todos?select=%2A&"
      + operators.map { "column=\($0).Some%20value" }.joined(separator: "&")
    #expect(request.renderedPath() == expected)
    #expect(request.queryValues(for: "column").count == 25)
  }

  @Test
  func rpcParametersRenderInTheOrderTheyWereAdded() {
    // The legacy `rpc call with get and params` snapshot is the one case that cannot be ported as
    // an exact string. `PostgrestClient.rpc(_:params:get:)` iterates a `JSONValue` object — a
    // Swift `Dictionary` — so it emits `index=2&array=...` on one run and `array=...&index=2` on
    // the next. Two captures of the same chain disagreed. The snapshot never caught it because
    // `.curl` sorts the query items before recording them.
    //
    // Parameter order does not change what PostgREST returns, so this is not a wire bug — but it
    // does make the request unreproducible in a log or a cache key. `PostgrestRequest` has no such
    // freedom: insertion order is send order. Whoever rebuilds `rpc` on it has to choose an order,
    // and this asserts the value model does not hand the ambiguity back.
    var request = PostgrestRequest(method: .get, path: "/rpc/get_array_element")
    request.appendQueryItem(name: "array", value: "{37,420,64}")
    request.appendQueryItem(name: "index", value: "2")

    #expect(request.renderedPath() == "/rpc/get_array_element?array=%7B37%2C420%2C64%7D&index=2")
  }

  struct WireFormatCase: Sendable, CustomStringConvertible {
    let name: String
    let method: HTTPTypes.HTTPRequest.Method
    let path: String
    let queryItems: [PostgrestRequest.QueryItem]
    let renderedPath: String

    var description: String { name }
  }

  /// 30 of the 32 requests recorded under `__Snapshots__/BuildURLRequestTests/`, re-expressed as
  /// assertions about ``PostgrestRequest`` rendering. The two left out have their own tests above:
  /// the 25-operator case, which reads better generated than transcribed, and the RPC-params case,
  /// whose legacy order is nondeterministic.
  ///
  /// The expected strings are **not** copied from the snapshot files. Those are written by
  /// swift-snapshot-testing's `.curl` strategy, which sorts the query items by name and re-encodes
  /// them through `URLComponents.queryItems` — so `select=%2A` is recorded as `select=*` and
  /// insertion order is lost. Each string below is the real `URLRequest.url` the legacy builder
  /// produces, captured by running the same 32 builder chains through a fetch handler that prints
  /// it.
  static let wireFormatCases: [WireFormatCase] = [
    .init(
      name: "select all users where email ends with '@supabase.co'",
      method: .get,
      path: "/users",
      queryItems: [
        .init(name: "select", value: "*"), .init(name: "email", value: "like.%@supabase.co"),
      ],
      renderedPath: "/users?select=%2A&email=like.%25%40supabase.co"
    ),
    .init(
      name: "insert new user",
      method: .post,
      path: "/users",
      queryItems: [],
      renderedPath: "/users"
    ),
    .init(
      name: "bulk insert users",
      method: .post,
      path: "/users",
      queryItems: [.init(name: "columns", value: "\"email\",\"username\"")],
      renderedPath: "/users?columns=%22email%22%2C%22username%22"
    ),
    .init(
      name: "call rpc",
      method: .post,
      path: "/rpc/test_fcn",
      queryItems: [],
      renderedPath: "/rpc/test_fcn"
    ),
    .init(
      name: "call rpc without parameter",
      method: .post,
      path: "/rpc/test_fcn",
      queryItems: [],
      renderedPath: "/rpc/test_fcn"
    ),
    .init(
      name: "call rpc with filter",
      method: .post,
      path: "/rpc/test_fcn",
      queryItems: [.init(name: "id", value: "eq.1")],
      renderedPath: "/rpc/test_fcn?id=eq.1"
    ),
    .init(
      name: "test in filter",
      method: .get,
      path: "/todos",
      queryItems: [.init(name: "select", value: "*"), .init(name: "id", value: "in.(1,2,3)")],
      renderedPath: "/todos?select=%2A&id=in.%281%2C2%2C3%29"
    ),
    .init(
      name: "test contains filter with dictionary",
      method: .get,
      path: "/users",
      queryItems: [
        .init(name: "select", value: "name"),
        .init(name: "address", value: "cs.{\"postcode\":90210}"),
      ],
      renderedPath: "/users?select=name&address=cs.%7B%22postcode%22%3A90210%7D"
    ),
    .init(
      name: "test contains filter with array",
      method: .get,
      path: "/users",
      queryItems: [
        .init(name: "select", value: "*"), .init(name: "name", value: "cs.{is:online,faction:red}"),
      ],
      renderedPath: "/users?select=%2A&name=cs.%7Bis%3Aonline%2Cfaction%3Ared%7D"
    ),
    .init(
      name: "test or filter with referenced table",
      method: .get,
      path: "/users",
      queryItems: [
        .init(name: "select", value: "*,messages(*)"),
        .init(name: "messages.or", value: "(public.eq.true,recipient_id.eq.1)"),
      ],
      renderedPath:
        "/users?select=%2A%2Cmessages%28%2A%29&messages.or=%28public.eq.true%2Crecipient_id.eq.1%29"
    ),
    .init(
      name: "test upsert not ignoring duplicates",
      method: .post,
      path: "/users",
      queryItems: [],
      renderedPath: "/users"
    ),
    .init(
      name: "bulk upsert",
      method: .post,
      path: "/users",
      queryItems: [.init(name: "columns", value: "\"email\",\"username\"")],
      renderedPath: "/users?columns=%22email%22%2C%22username%22"
    ),
    .init(
      name: "select after bulk upsert",
      method: .post,
      path: "/users",
      queryItems: [
        .init(name: "on_conflict", value: "username"), .init(name: "columns", value: "\"email\""),
        .init(name: "select", value: "*"),
      ],
      renderedPath: "/users?on_conflict=username&columns=%22email%22&select=%2A"
    ),
    .init(
      name: "test upsert ignoring duplicates",
      method: .post,
      path: "/users",
      queryItems: [],
      renderedPath: "/users"
    ),
    .init(
      name: "query with + character",
      method: .get,
      path: "/users",
      queryItems: [
        .init(name: "select", value: "*"),
        .init(name: "id", value: "eq.Cigányka-ér (0+400 cskm) vízrajzi állomás"),
      ],
      renderedPath:
        "/users?select=%2A&id=eq.Cig%C3%A1nyka-%C3%A9r%20%280%2B400%20cskm%29%20v%C3%ADzrajzi%20%C3%A1llom%C3%A1s"
    ),
    .init(
      name: "query with timestamptz",
      method: .get,
      path: "/tasks",
      queryItems: [
        .init(name: "select", value: "*"),
        .init(name: "received_at", value: "gt.2023-03-23T15:50:30.511743+00:00"),
        .init(name: "order", value: "received_at.asc.nullslast"),
      ],
      renderedPath:
        "/tasks?select=%2A&received_at=gt.2023-03-23T15%3A50%3A30.511743%2B00%3A00&order=received_at.asc.nullslast"
    ),
    .init(
      name: "query non-default schema",
      method: .get,
      path: "/objects",
      queryItems: [.init(name: "select", value: "*")],
      renderedPath: "/objects?select=%2A"
    ),
    .init(
      name: "select after an insert",
      method: .post,
      path: "/users",
      queryItems: [.init(name: "select", value: "id,email")],
      renderedPath: "/users?select=id%2Cemail"
    ),
    .init(
      name: "query if nil value",
      method: .get,
      path: "/users",
      queryItems: [.init(name: "select", value: "*"), .init(name: "email", value: "is.NULL")],
      renderedPath: "/users?select=%2A&email=is.NULL"
    ),
    .init(
      name: "likeAllOf",
      method: .get,
      path: "/users",
      queryItems: [
        .init(name: "select", value: "*"),
        .init(name: "email", value: "like(all).{%@supabase.io,%@supabase.com}"),
      ],
      renderedPath:
        "/users?select=%2A&email=like%28all%29.%7B%25%40supabase.io%2C%25%40supabase.com%7D"
    ),
    .init(
      name: "likeAnyOf",
      method: .get,
      path: "/users",
      queryItems: [
        .init(name: "select", value: "*"),
        .init(name: "email", value: "like(any).{%@supabase.io,%@supabase.com}"),
      ],
      renderedPath:
        "/users?select=%2A&email=like%28any%29.%7B%25%40supabase.io%2C%25%40supabase.com%7D"
    ),
    .init(
      name: "iLikeAllOf",
      method: .get,
      path: "/users",
      queryItems: [
        .init(name: "select", value: "*"),
        .init(name: "email", value: "ilike(all).{%@supabase.io,%@supabase.com}"),
      ],
      renderedPath:
        "/users?select=%2A&email=ilike%28all%29.%7B%25%40supabase.io%2C%25%40supabase.com%7D"
    ),
    .init(
      name: "iLikeAnyOf",
      method: .get,
      path: "/users",
      queryItems: [
        .init(name: "select", value: "*"),
        .init(name: "email", value: "ilike(any).{%@supabase.io,%@supabase.com}"),
      ],
      renderedPath:
        "/users?select=%2A&email=ilike%28any%29.%7B%25%40supabase.io%2C%25%40supabase.com%7D"
    ),
    .init(
      name: "containedBy using array",
      method: .get,
      path: "/users",
      queryItems: [.init(name: "select", value: "*"), .init(name: "id", value: "cd.{a,b,c}")],
      renderedPath: "/users?select=%2A&id=cd.%7Ba%2Cb%2Cc%7D"
    ),
    .init(
      name: "containedBy using range",
      method: .get,
      path: "/users",
      queryItems: [.init(name: "select", value: "*"), .init(name: "age", value: "cd.[10,20]")],
      renderedPath: "/users?select=%2A&age=cd.%5B10%2C20%5D"
    ),
    .init(
      name: "containedBy using json",
      method: .get,
      path: "/users",
      queryItems: [
        .init(name: "select", value: "*"), .init(name: "userMetadata", value: "cd.{\"age\":18}"),
      ],
      renderedPath: "/users?select=%2A&userMetadata=cd.%7B%22age%22%3A18%7D"
    ),
    .init(
      name: "filter starting with non-alphanumeric",
      method: .get,
      path: "/users",
      queryItems: [.init(name: "select", value: "*"), .init(name: "to", value: "eq.+16505555555")],
      renderedPath: "/users?select=%2A&to=eq.%2B16505555555"
    ),
    .init(
      name: "filter using Date",
      method: .get,
      path: "/users",
      queryItems: [
        .init(name: "select", value: "*"),
        .init(name: "created_at", value: "gt.1970-01-01T00:00:00.000Z"),
      ],
      renderedPath: "/users?select=%2A&created_at=gt.1970-01-01T00%3A00%3A00.000Z"
    ),
    .init(
      name: "rpc call with head",
      method: .head,
      path: "/rpc/sum",
      queryItems: [],
      renderedPath: "/rpc/sum"
    ),
    .init(
      name: "rpc call with get",
      method: .get,
      path: "/rpc/sum",
      queryItems: [],
      renderedPath: "/rpc/sum"
    ),
  ]

  @Test(arguments: wireFormatCases)
  func matchesTheLegacyWireFormat(_ testCase: WireFormatCase) {
    let request = PostgrestRequest(
      method: testCase.method,
      path: testCase.path,
      queryItems: testCase.queryItems
    )

    #expect(request.renderedPath() == testCase.renderedPath)
    #expect(request.httpRequest(baseURL: baseURL).method == testCase.method)
  }
}
