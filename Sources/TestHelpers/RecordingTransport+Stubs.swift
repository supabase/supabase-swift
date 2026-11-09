//
//  RecordingTransport+Stubs.swift
//  TestHelpers
//
//  Created by Guilherme Souza on 09/11/26.
//

package import Foundation
package import HTTPTypes
import Helpers
import InlineSnapshotTesting
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension RecordingTransport {
  /// Answers `method` requests to `url` with `status`, `data`, and `headers`.
  ///
  /// A request matches when its method and path are equal to the stub's and every pair in `query`
  /// is among its query items. An empty `query` matches any query string. When two stubs match,
  /// the one registered first answers.
  ///
  /// The response gets `Content-Type: application/json` when `data` is JSON and `headers` has no
  /// content type.
  ///
  /// The trailing closure is an inline snapshot of the matching request, in curl form. It is
  /// compared in the task that sends the request, so a mismatch fails the test that sends it.
  /// Linux skips it, as the curl snapshot differs there.
  package func stub(
    _ method: HTTPRequest.Method,
    _ url: URL,
    query: KeyValuePairs<String, String> = [:],
    status: HTTPResponse.Status = .ok,
    data: Data = Data(),
    headers: HTTPFields = [:],
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    function: StaticString = #function,
    line: UInt = #line,
    column: UInt = #column,
    snapshot: (() -> String)? = nil
  ) {
    let expected = snapshot?()
    var fields = headers
    if fields[.contentType] == nil,
      (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil
    {
      fields[.contentType] = "application/json"
    }
    stub(method, url, query: query) { [fields] request, body in
      #if !os(Linux) && !os(Android)
        if let expected {
          assertInlineSnapshot(
            of: try Self.curlRequest(request, body: body), as: ._curl, matches: { expected },
            fileID: fileID, file: filePath, function: function, line: line, column: column)
        }
      #endif
      return (HTTPResponse(status: status, headerFields: fields), data)
    }
  }

  /// Compares the first `method` request to `url` with an inline snapshot, in curl form, for a
  /// test whose stub is the closure form of ``stub(_:_:query:_:)``, which has no snapshot of its
  /// own.
  ///
  /// Linux skips it, as the curl snapshot differs there.
  package func assertFirstRequestSnapshot(
    _ method: HTTPRequest.Method,
    _ url: URL,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    function: StaticString = #function,
    line: UInt = #line,
    column: UInt = #column,
    matches expected: (() -> String)? = nil
  ) throws {
    #if !os(Linux) && !os(Android)
      let (head, body) = try #require(requests(method, url).first)
      assertInlineSnapshot(
        of: try Self.curlRequest(head, body: body), as: ._curl, matches: expected,
        fileID: fileID, file: filePath, function: function, line: line, column: column)
    #endif
  }

  /// Answers `method` requests to `url` with whatever `handler` returns or throws.
  package func stub(
    _ method: HTTPRequest.Method,
    _ url: URL,
    query: KeyValuePairs<String, String> = [:],
    _ handler: @escaping Handler
  ) {
    respond(when: Self.matches(method, url, query.map { ($0.key, $0.value) }), handler)
  }

  /// Requests received so far for `method` and `url`, in order, with their buffered bodies.
  package func requests(
    _ method: HTTPRequest.Method, _ url: URL
  ) -> [(head: HTTPRequest, body: Data?)] {
    let matches = Self.matches(method, url, [])
    return requests.filter { matches($0.head) }
  }

  /// `request` and `body` as the `URLRequest` that `URLSession` would send, for a curl snapshot.
  ///
  /// `URLSession` sets `Content-Length` from the body, so it is added here when it is missing.
  private static func curlRequest(_ request: HTTPRequest, body: Data?) throws -> URLRequest {
    guard var urlRequest = URLRequest(httpRequest: request) else { throw URLError(.badURL) }
    urlRequest.httpBody = body
    if let body, urlRequest.value(forHTTPHeaderField: "Content-Length") == nil {
      urlRequest.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
    }
    return urlRequest
  }

  private static func matches(
    _ method: HTTPRequest.Method, _ url: URL, _ query: [(String, String)]
  ) -> @Sendable (HTTPRequest) -> Bool {
    let expectedPath = url.path
    return { request in
      guard request.method == method, let url = request.url, url.path == expectedPath else {
        return false
      }
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      return query.allSatisfy { name, value in
        items.contains { $0.name == name && $0.value == value }
      }
    }
  }
}
