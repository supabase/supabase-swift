//
//  SupabaseClientTransportTests.swift
//  Helpers
//
//  Created by Guilherme Souza on 30/06/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import Helpers

@Suite("SupabaseClientTransport", .serialized)
struct SupabaseClientTransportTests {
  @Test("sends request to correct URL")
  func sendsToCorrectURL() async throws {
    let box = RequestBox()
    let session = URLSession.mockSession { request in
      box.value = request
      return (
        Data("{}".utf8),
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      )
    }

    let transport = SupabaseClientTransport(session: session, tokenProvider: nil)
    let baseURL = URL(string: "https://example.supabase.co/storage/v1")!
    let httpRequest = HTTPTypes.HTTPRequest(
      method: .get, scheme: nil, authority: nil, path: "/bucket")

    _ = try await transport.send(
      httpRequest, body: nil, baseURL: baseURL, operationID: "listBuckets")

    #expect(box.value?.url?.absoluteString == "https://example.supabase.co/storage/v1/bucket")
    #expect(box.value?.httpMethod == "GET")
  }

  @Test("injects Bearer token when tokenProvider returns a token")
  func injectsToken() async throws {
    let box = RequestBox()
    let session = URLSession.mockSession { request in
      box.value = request
      return (
        Data(),
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      )
    }

    let transport = SupabaseClientTransport(session: session, tokenProvider: { "test-token" })
    let baseURL = URL(string: "https://example.supabase.co/storage/v1")!
    let httpRequest = HTTPTypes.HTTPRequest(
      method: .get, scheme: nil, authority: nil, path: "/bucket")

    _ = try await transport.send(
      httpRequest, body: nil, baseURL: baseURL, operationID: "listBuckets")

    #expect(box.value?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
  }

  @Test("does not overwrite existing Authorization header")
  func doesNotOverwriteAuth() async throws {
    let box = RequestBox()
    let session = URLSession.mockSession { request in
      box.value = request
      return (
        Data(),
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      )
    }

    let transport = SupabaseClientTransport(session: session, tokenProvider: { "injected-token" })
    let baseURL = URL(string: "https://example.supabase.co/storage/v1")!
    var httpRequest = HTTPTypes.HTTPRequest(
      method: .get, scheme: nil, authority: nil, path: "/bucket")
    httpRequest.headerFields[.authorization] = "Bearer caller-token"

    _ = try await transport.send(
      httpRequest, body: nil, baseURL: baseURL, operationID: "listBuckets")

    #expect(box.value?.value(forHTTPHeaderField: "Authorization") == "Bearer caller-token")
  }
}

// MARK: - Thread-safe capture box

final class RequestBox: @unchecked Sendable {
  private let _value = LockIsolated<URLRequest?>(nil)
  var value: URLRequest? {
    get { _value.value }
    set { _value.withValue { $0 = newValue } }
  }
}

// MARK: - URLSession mock helper

extension URLSession {
  static func mockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
  ) -> URLSession {
    MockURLProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
  }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler:
    (@Sendable (URLRequest) throws -> (Data, HTTPURLResponse))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = MockURLProtocol.handler else { return }
    do {
      let (data, response) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
