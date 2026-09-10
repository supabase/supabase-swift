//
//  HTTPClientTests.swift
//  HelpersTests
//
//  Created by Guilherme Souza on 09/09/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Testing

@testable import Helpers

@Suite
struct HTTPClientTests {
  struct StubTransport: ClientTransport {
    let seen: LockIsolated<[(HTTPTypes.HTTPRequest, HTTPBody?)]>
    let respond: @Sendable () -> (HTTPTypes.HTTPResponse, HTTPBody?)

    func send(_ request: HTTPTypes.HTTPRequest, body: HTTPBody?) async throws -> (
      HTTPTypes.HTTPResponse, HTTPBody?
    ) {
      seen.withValue { $0.append((request, body)) }
      #expect(RequestTimeout.current == 42)
      return respond()
    }
  }

  struct TagMiddleware: ClientMiddleware {
    let tag: String
    let log: LockIsolated<[String]>

    func intercept(
      _ request: HTTPTypes.HTTPRequest, body: HTTPBody?,
      next:
        @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
          HTTPTypes.HTTPResponse, HTTPBody?
        )
    ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
      log.withValue { $0.append("\(tag):request") }
      var request = request
      request.headerFields[HTTPField.Name("X-\(tag)")!] = "1"
      let result = try await next(request, body)
      log.withValue { $0.append("\(tag):response") }
      return result
    }
  }

  @Test
  func middlewaresRunInOrderAndTransportSeesTheFinalRequest() async throws {
    let seen = LockIsolated<[(HTTPTypes.HTTPRequest, HTTPBody?)]>([])
    let log = LockIsolated<[String]>([])
    let client = HTTPClient(
      transport: StubTransport(seen: seen) {
        (HTTPTypes.HTTPResponse(status: .ok), HTTPBody(Data("[]".utf8)))
      },
      middlewares: [TagMiddleware(tag: "A", log: log), TagMiddleware(tag: "B", log: log)]
    )

    let response = try await client.send(
      HTTPRequest(
        url: URL(string: "https://example.com/rest")!, method: .post,
        query: [URLQueryItem(name: "select", value: "*")],
        body: Data("{}".utf8), timeoutInterval: 42)
    )

    #expect(log.value == ["A:request", "B:request", "B:response", "A:response"])
    let sent = try #require(seen.value.first)
    #expect(sent.0.url?.absoluteString == "https://example.com/rest?select=%2A")
    #expect(sent.0.method == .post)
    #expect(sent.0.headerFields[HTTPField.Name("X-A")!] == "1")
    #expect(sent.0.headerFields[HTTPField.Name("X-B")!] == "1")
    #expect(sent.0.headerFields[.contentType] == "application/json")
    #expect(sent.1?.length == .known(2))
    #expect(response.statusCode == 200)
    #expect(response.data == Data("[]".utf8))
    #expect(
      response.underlyingResponse.url?.absoluteString == "https://example.com/rest?select=%2A")
  }

  @Test
  func bodilessRequestSendsNoBodyAndNoContentType() async throws {
    let seen = LockIsolated<[(HTTPTypes.HTTPRequest, HTTPBody?)]>([])
    let client = HTTPClient(
      transport: StubTransport(seen: seen) { (HTTPTypes.HTTPResponse(status: .noContent), nil) },
      middlewares: []
    )

    let response = try await client.send(
      HTTPRequest(url: URL(string: "https://example.com")!, method: .get, timeoutInterval: 42))

    let sent = try #require(seen.value.first)
    #expect(sent.1 == nil)
    #expect(sent.0.headerFields[.contentType] == nil)
    #expect(response.data.isEmpty)
    #expect(response.statusCode == 204)
  }

  @Test
  func streamReturnsTheHeadBeforeTheBodyFinishes() async throws {
    let (chunks, continuation) = AsyncStream<ArraySlice<UInt8>>.makeStream()
    let seen = LockIsolated<[(HTTPTypes.HTTPRequest, HTTPBody?)]>([])
    let client = HTTPClient(
      transport: StubTransport(seen: seen) {
        (
          HTTPTypes.HTTPResponse(status: .ok),
          HTTPBody(chunks, length: .unknown, iterationBehavior: .single)
        )
      },
      middlewares: []
    )

    let (head, body) = try await client.stream(
      HTTPRequest(url: URL(string: "https://example.com")!, method: .get, timeoutInterval: 42))
    #expect(head.status == .ok)

    continuation.yield(ArraySlice("data: 1\n".utf8))
    var iterator = try #require(body).makeAsyncIterator()
    #expect(try await iterator.next() == ArraySlice("data: 1\n".utf8))
    continuation.finish()
    #expect(try await iterator.next() == nil)
  }
}
