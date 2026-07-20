//
//  HTTPStub.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
package import HTTPRuntime

/// A canned response for one request, matched by HTTP method + full URL
/// (including query), consumed in the order it appears in `.http(stubs:)`'s
/// array. Only ever describes the *response* — see `assertHTTPRequests` to
/// assert the shape of the outgoing request.
package struct HTTPStub: Sendable {
  package let method: HTTPMethod
  package let url: String
  package let status: Int
  package let headers: [String: String]
  package let body: @Sendable () -> HTTPStubBody

  private init(
    method: HTTPMethod, url: String, status: Int, headers: [String: String],
    body: @escaping @Sendable () -> HTTPStubBody
  ) {
    self.method = method
    self.url = url
    self.status = status
    self.headers = headers
    self.body = body
  }

  package static func get(
    _ url: String, status: Int = 200, headers: [String: String] = [:],
    body: @escaping @Sendable () -> HTTPStubBody = { .empty }
  ) -> HTTPStub {
    HTTPStub(method: .get, url: url, status: status, headers: headers, body: body)
  }

  package static func post(
    _ url: String, status: Int = 200, headers: [String: String] = [:],
    body: @escaping @Sendable () -> HTTPStubBody = { .empty }
  ) -> HTTPStub {
    HTTPStub(method: .post, url: url, status: status, headers: headers, body: body)
  }

  package static func put(
    _ url: String, status: Int = 200, headers: [String: String] = [:],
    body: @escaping @Sendable () -> HTTPStubBody = { .empty }
  ) -> HTTPStub {
    HTTPStub(method: .put, url: url, status: status, headers: headers, body: body)
  }

  package static func patch(
    _ url: String, status: Int = 200, headers: [String: String] = [:],
    body: @escaping @Sendable () -> HTTPStubBody = { .empty }
  ) -> HTTPStub {
    HTTPStub(method: .patch, url: url, status: status, headers: headers, body: body)
  }

  package static func delete(
    _ url: String, status: Int = 200, headers: [String: String] = [:],
    body: @escaping @Sendable () -> HTTPStubBody = { .empty }
  ) -> HTTPStub {
    HTTPStub(method: .delete, url: url, status: status, headers: headers, body: body)
  }

  package static func head(
    _ url: String, status: Int = 200, headers: [String: String] = [:],
    body: @escaping @Sendable () -> HTTPStubBody = { .empty }
  ) -> HTTPStub {
    HTTPStub(method: .head, url: url, status: status, headers: headers, body: body)
  }
}
