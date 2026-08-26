//
//  PostgrestTransportTests.swift
//  PostgREST
//
//  Created by Guilherme Souza on 22/08/26.
//

import ConcurrencyExtras
import Foundation
import HTTPRuntime
import HTTPTypes
import Mocker
import TestHelpers
import Testing

@testable import PostgREST

/// A transport that records what it was handed and replies with whatever it was told to.
private struct RecordingTransport: PostgrestTransport {
  let recorded = LockIsolated<[(request: HTTPTypes.HTTPRequest, body: Data?)]>([])
  var status = 200
  var responseHeaderFields = HTTPTypes.HTTPFields()
  var responseBody = Data()
  var failure: (any Error)?

  func send(
    _ request: HTTPTypes.HTTPRequest, body: Data?
  ) async throws -> (Data, HTTPTypes.HTTPResponse) {
    recorded.withValue { $0.append((request, body)) }
    if let failure { throw failure }
    return (
      responseBody,
      HTTPTypes.HTTPResponse(status: .init(code: status), headerFields: responseHeaderFields)
    )
  }
}

private struct StubFailure: Error, Equatable {}

@Suite
struct PostgrestTransportTests {

  // MARK: - Request conversion

  @Test
  func passesMethodSchemeAuthorityAndPathThrough() async throws {
    let transport = RecordingTransport()

    _ = try await PostgrestTransportBridge(transport: transport).send(
      HTTPRuntime.HTTPRequest(
        method: .post,
        url: URL(string: "https://example.supabase.co/rest/v1/todos")!
      ))

    let sent = try #require(transport.recorded.value.first).request
    #expect(sent.method == .post)
    #expect(sent.scheme == "https")
    #expect(sent.authority == "example.supabase.co")
    #expect(sent.path == "/rest/v1/todos")
  }

  @Test
  func keepsThePathAndQueryPercentEncoded() async throws {
    // The trap in this conversion. `URL.path` and `URLComponents.path` both decode, so reading
    // either would hand the transport `select=*` where the wire carries `select=%2A` — and
    // PostgREST's encoding is deliberately stricter than Foundation's default.
    let transport = RecordingTransport()
    let url = URL(
      string: "https://example.supabase.co/todos?select=%2A&to=eq.%2B16505555555&c=eq.a%20b")!

    _ = try await PostgrestTransportBridge(transport: transport).send(
      HTTPRuntime.HTTPRequest(method: .get, url: url))

    let sent = try #require(transport.recorded.value.first).request
    #expect(sent.path == "/todos?select=%2A&to=eq.%2B16505555555&c=eq.a%20b")
  }

  @Test
  func keepsAnExplicitPort() async throws {
    let transport = RecordingTransport()

    _ = try await PostgrestTransportBridge(transport: transport).send(
      HTTPRuntime.HTTPRequest(
        method: .get, url: URL(string: "http://localhost:54321/rest/v1/todos")!))

    let sent = try #require(transport.recorded.value.first).request
    #expect(sent.authority == "localhost:54321")
    #expect(sent.path == "/rest/v1/todos")
  }

  @Test
  func passesHeadersThrough() async throws {
    let transport = RecordingTransport()

    _ = try await PostgrestTransportBridge(transport: transport).send(
      HTTPRuntime.HTTPRequest(
        method: .get,
        url: URL(string: "https://example.supabase.co/todos")!,
        headers: ["Prefer": "count=exact", "Accept-Profile": "storage"]
      ))

    let sent = try #require(transport.recorded.value.first).request
    #expect(sent.headerFields[.init("Prefer")!] == "count=exact")
    #expect(sent.headerFields[.init("Accept-Profile")!] == "storage")
  }

  @Test
  func passesADataBodyThroughUntouched() async throws {
    let transport = RecordingTransport()
    let body = Data(#"{"email":"johndoe@supabase.io"}"#.utf8)

    _ = try await PostgrestTransportBridge(transport: transport).send(
      HTTPRuntime.HTTPRequest(
        method: .post, url: URL(string: "https://example.supabase.co/users")!, body: .data(body)))

    #expect(try #require(transport.recorded.value.first).body == body)
  }

  @Test
  func passesNoBodyAsNil() async throws {
    let transport = RecordingTransport()

    _ = try await PostgrestTransportBridge(transport: transport).send(
      HTTPRuntime.HTTPRequest(method: .get, url: URL(string: "https://example.supabase.co/todos")!))

    #expect(try #require(transport.recorded.value.first).body == nil)
  }

  @Test
  func refusesAFileBackedBodyRatherThanBufferingIt() async throws {
    // Reading the file in would defeat the reason `.file` exists. PostgREST never produces one, so
    // this asserts the boundary is explicit rather than accidentally lenient.
    let transport = RecordingTransport()
    let request = HTTPRuntime.HTTPRequest(
      method: .post,
      url: URL(string: "https://example.supabase.co/users")!,
      body: .file(URL(fileURLWithPath: "/tmp/upload.bin"))
    )

    await #expect(throws: HTTPRuntime.HTTPError.self) {
      _ = try await PostgrestTransportBridge(transport: transport).send(request)
    }
    #expect(transport.recorded.value.isEmpty)
  }

  // MARK: - Response conversion

  @Test
  func convertsTheResponseStatusHeadersAndBody() async throws {
    var transport = RecordingTransport()
    transport.status = 206
    transport.responseHeaderFields = [.contentRange: "0-9/100"]
    transport.responseBody = Data("[]".utf8)

    let response = try await PostgrestTransportBridge(transport: transport).send(
      HTTPRuntime.HTTPRequest(method: .get, url: URL(string: "https://example.supabase.co/todos")!))

    #expect(response.head.status == 206)
    #expect(response.head.header("Content-Range") == "0-9/100")
    #expect(response.body == Data("[]".utf8))
  }

  // MARK: - Failure paths

  @Test
  func wrapsATransportErrorRatherThanLosingIt() async throws {
    var transport = RecordingTransport()
    transport.failure = StubFailure()

    let error = await #expect(throws: HTTPRuntime.HTTPError.self) {
      _ = try await PostgrestTransportBridge(transport: transport).send(
        HTTPRuntime.HTTPRequest(
          method: .get, url: URL(string: "https://example.supabase.co/todos")!))
    }

    guard case .transport(let underlying) = try #require(error) else {
      Issue.record("expected .transport, got \(String(describing: error))")
      return
    }
    #expect(underlying as? StubFailure == StubFailure())
  }

  @Test
  func refusesToStream() async throws {
    // A `PostgrestTransport` returns a buffered response, so it cannot stream. Buffering the whole
    // body and handing back a one-chunk stream would look like streaming while defeating it.
    let transport = RecordingTransport()

    await #expect(throws: HTTPRuntime.HTTPError.self) {
      _ = try await PostgrestTransportBridge(transport: transport).stream(
        HTTPRuntime.HTTPRequest(
          method: .get, url: URL(string: "https://example.supabase.co/todos")!))
    }
  }

  // MARK: - Conversion helpers

  @Test
  func repeatedHeaderFieldsJoinWithACommaPerRFC9110() {
    var fields = HTTPTypes.HTTPFields()
    fields.append(HTTPTypes.HTTPField(name: .init("Prefer")!, value: "count=exact"))
    fields.append(HTTPTypes.HTTPField(name: .init("Prefer")!, value: "return=representation"))

    #expect(
      postgrestHeaderDictionary(from: fields)["Prefer"] == "count=exact, return=representation")
  }

  @Test
  func mergesRepeatedHeaderNamesRegardlessOfCasing() {
    // Otherwise `Prefer` and `prefer` become two dictionary entries and whichever consumer looks
    // the header up sees only one of them.
    var fields = HTTPTypes.HTTPFields()
    fields.append(HTTPTypes.HTTPField(name: .init("Prefer")!, value: "count=exact"))
    fields.append(HTTPTypes.HTTPField(name: .init("prefer")!, value: "return=representation"))

    let headers = postgrestHeaderDictionary(from: fields)

    #expect(headers.count == 1)
    #expect(headers["Prefer"] == "count=exact, return=representation")
  }

  @Test
  func rebuildsTheURLWithoutDecodingTheQuery() throws {
    let request = HTTPTypes.HTTPRequest(
      method: .get,
      scheme: "https",
      authority: "example.supabase.co",
      path: "/todos?select=%2A&to=eq.%2B16505555555"
    )

    let url = try postgrestRequestURL(from: request)

    #expect(
      url.absoluteString
        == "https://example.supabase.co/todos?select=%2A&to=eq.%2B16505555555")
  }

  @Test
  func reportsAMethodHTTPRuntimeCannotExpress() {
    // `OPTIONS` is a valid `HTTPTypes` method with no `HTTPRuntime.HTTPMethod` case. PostgREST
    // never sends one, so this asserts the gap fails loudly instead of defaulting to GET.
    #expect(throws: HTTPRuntime.HTTPError.self) {
      _ = try postgrestHTTPMethod(from: HTTPTypes.HTTPRequest.Method.options)
    }
  }

  @Test
  func mapsEveryHTTPRuntimeMethod() {
    let expected: [(HTTPRuntime.HTTPMethod, HTTPTypes.HTTPRequest.Method)] = [
      (.get, .get), (.post, .post), (.put, .put), (.patch, .patch), (.delete, .delete),
      (.head, .head),
    ]

    for (runtime, types) in expected {
      #expect(postgrestHTTPMethod(from: runtime) == types)
    }
  }
}

extension PostgrestMockerTests {
  @Suite(.mockerSerialized)
  struct URLSessionPostgrestTransportTests {
    /// Exercises the shipped implementation against a real `URLSession`, so the URL reassembly is
    /// checked by URLSession's own parser rather than only by an assertion on a string.
    private func transport() -> URLSessionPostgrestTransport {
      let configuration = URLSessionConfiguration.default
      configuration.protocolClasses = [MockingURLProtocol.self]
      return URLSessionPostgrestTransport(configuration: configuration)
    }

    @Test
    func sendsAndReturnsTheResponse() async throws {
      Mock(
        url: URL(string: "http://localhost:54321/rest/v1/todos")!,
        ignoreQuery: true,
        statusCode: 206,
        data: [.get: Data("[]".utf8)],
        additionalHeaders: ["Content-Range": "0-9/100"]
      )
      .register()

      let (data, response) = try await transport().send(
        HTTPTypes.HTTPRequest(
          method: .get,
          scheme: "http",
          authority: "localhost:54321",
          path: "/rest/v1/todos?select=%2A"
        ),
        body: nil
      )

      #expect(response.status.code == 206)
      #expect(response.headerFields[.contentRange] == "0-9/100")
      #expect(data == Data("[]".utf8))
    }

    @Test
    func sendsTheQueryStringExactlyAsGiven() async throws {
      // The round trip that matters: a strictly-escaped query has to survive URL reassembly and
      // URLSession without being normalized back to its permissive spelling.
      //
      // Asserted on the recorded `URLRequest.url` rather than with `Mock.snapshotRequest`, because
      // a curl snapshot cannot see this. That renderer sorts the query items and re-encodes them
      // through `URLComponents`, which turns `%2A` back into `*` and `%2B` back into `+` — the
      // exact regression this test exists to catch. Verified: the snapshot form of this assertion
      // recorded `?select=*&to=eq.+16505555555` while the wire carried the escaped spelling.
      let sent = LockIsolated<URLRequest?>(nil)
      var mock = Mock(
        url: URL(string: "http://localhost:54321/rest/v1/todos")!,
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      // Mocker calls this on the URL-loading queue, where Swift Testing has no current test, so a
      // recorded issue there would be dropped. Capture now, assert after `send` returns.
      mock.onRequestHandler = OnRequestHandler { request in
        sent.setValue(request)
      }
      mock.register()

      _ = try await transport().send(
        HTTPTypes.HTTPRequest(
          method: .get,
          scheme: "http",
          authority: "localhost:54321",
          path: "/rest/v1/todos?select=%2A&to=eq.%2B16505555555"
        ),
        body: nil
      )

      let url = try #require(sent.value?.url)
      #expect(
        url.absoluteString
          == "http://localhost:54321/rest/v1/todos?select=%2A&to=eq.%2B16505555555")
    }

    @Test
    func sendsABody() async throws {
      let body = Data(#"{"email":"johndoe@supabase.io"}"#.utf8)
      Mock(
        url: URL(string: "http://localhost:54321/rest/v1/users")!,
        ignoreQuery: true,
        statusCode: 201,
        data: [.post: Data()]
      )
      .register()

      let (_, response) = try await transport().send(
        HTTPTypes.HTTPRequest(
          method: .post,
          scheme: "http",
          authority: "localhost:54321",
          path: "/rest/v1/users"
        ),
        body: body
      )

      #expect(response.status.code == 201)
    }
  }
}
