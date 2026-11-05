import ConcurrencyExtras
import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Helpers
import InlineSnapshotTesting
import TestHelpers

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension RecordingTransport {
  /// Answers `method` requests to `path` (under `clientURL`) with `status` and `data`.
  ///
  /// A request matches when its method and path are equal to the stub's and every pair in `query`
  /// is among its query items. An empty `query` matches any query string. When two stubs match,
  /// the one registered first answers.
  ///
  /// The trailing closure is an inline snapshot of the matching request, in curl form. It is
  /// compared in the task that sends the request, so a mismatch fails the test that owns the
  /// transport. Linux skips it, as the curl snapshot differs there.
  func stub(
    _ method: HTTPRequest.Method,
    _ path: String,
    query: KeyValuePairs<String, String> = [:],
    status: HTTPResponse.Status = .ok,
    data: Data = Data(),
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    function: StaticString = #function,
    line: UInt = #line,
    column: UInt = #column,
    snapshot: (() -> String)? = nil
  ) {
    let query = query.map { ($0.key, $0.value) }
    respond(
      when: Self.matches(method, path, query),
      Self.answer(
        status: status, data: data, fileID: fileID, filePath: filePath, function: function,
        line: line, column: column, snapshot: snapshot))
  }

  /// Answers `method` requests to `path` with whatever `handler` returns or throws.
  func stub(
    _ method: HTTPRequest.Method,
    _ path: String,
    query: KeyValuePairs<String, String> = [:],
    _ handler: @escaping Handler
  ) {
    let query = query.map { ($0.key, $0.value) }
    respond(when: Self.matches(method, path, query), handler)
  }

  /// Requests received so far for `method` and `path`, in order, with their buffered bodies.
  func requests(
    _ method: HTTPRequest.Method, _ path: String
  ) -> [(head: HTTPRequest, body: Data?)] {
    let matches = Self.matches(method, path, [])
    return requests.filter { matches($0.head) }
  }

  /// The JSON body of the last `method` request to `path`, or `nil` when none had a body.
  func lastJSONBody(_ method: HTTPRequest.Method, _ path: String) throws -> JSONValue? {
    guard let body = requests(method, path).last?.body else { return nil }
    return try JSONDecoder().decode(JSONValue.self, from: body)
  }

  private static func matches(
    _ method: HTTPRequest.Method, _ path: String, _ query: [(String, String)]
  ) -> @Sendable (HTTPRequest) -> Bool {
    let expectedPath = clientURL.appendingPathComponent(path).path
    return { request in
      guard request.method == method, let url = request.url, url.path == expectedPath else {
        return false
      }
      let items =
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      return query.allSatisfy { name, value in
        items.contains { $0.name == name && $0.value == value }
      }
    }
  }

  private static func answer(
    status: HTTPResponse.Status,
    data: Data,
    fileID: StaticString,
    filePath: StaticString,
    function: StaticString,
    line: UInt,
    column: UInt,
    snapshot: (() -> String)?
  ) -> Handler {
    let expected = snapshot?()
    let isSnapshotting = snapshot != nil
    return { request, body in
      #if !os(Linux) && !os(Android)
        if isSnapshotting, var urlRequest = URLRequest(httpRequest: request) {
          urlRequest.httpBody = body
          if let body, urlRequest.value(forHTTPHeaderField: "Content-Length") == nil {
            urlRequest.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
          }
          assertInlineSnapshot(
            of: urlRequest, as: ._curl,
            matches: expected.map { expected in { expected } },
            fileID: fileID, file: filePath, function: function, line: line, column: column)
        }
      #endif
      var fields = HTTPFields()
      if !data.isEmpty { fields[.contentType] = "application/json" }
      return (HTTPResponse(status: status, headerFields: fields), data)
    }
  }
}
