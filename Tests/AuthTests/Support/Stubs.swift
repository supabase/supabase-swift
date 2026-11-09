import Foundation
import HTTPTypes
import Helpers
import TestHelpers

@testable import Auth

extension RecordingTransport {
  /// Answers `method` requests to `path` (under `clientURL`) with `status` and `data`.
  ///
  /// See ``RecordingTransport/stub(_:_:query:status:data:headers:fileID:filePath:function:line:column:snapshot:)``
  /// for how requests match and how the trailing snapshot is compared.
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
    stub(
      method, clientURL.appendingPathComponent(path), query: query, status: status, data: data,
      fileID: fileID, filePath: filePath, function: function, line: line, column: column,
      snapshot: snapshot)
  }

  /// Answers `method` requests to `path` with whatever `handler` returns or throws.
  func stub(
    _ method: HTTPRequest.Method,
    _ path: String,
    query: KeyValuePairs<String, String> = [:],
    _ handler: @escaping Handler
  ) {
    stub(method, clientURL.appendingPathComponent(path), query: query, handler)
  }

  /// Requests received so far for `method` and `path`, in order, with their buffered bodies.
  func requests(
    _ method: HTTPRequest.Method, _ path: String
  ) -> [(head: HTTPRequest, body: Data?)] {
    requests(method, clientURL.appendingPathComponent(path))
  }

  /// Compares the first `method` request to `path` with an inline snapshot, in curl form.
  func assertFirstRequestSnapshot(
    _ method: HTTPRequest.Method,
    _ path: String,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    function: StaticString = #function,
    line: UInt = #line,
    column: UInt = #column,
    matches expected: (() -> String)? = nil
  ) throws {
    try assertFirstRequestSnapshot(
      method, clientURL.appendingPathComponent(path), fileID: fileID, filePath: filePath,
      function: function, line: line, column: column, matches: expected)
  }

  /// The JSON body of the last `method` request to `path`, or `nil` when none had a body.
  func lastJSONBody(_ method: HTTPRequest.Method, _ path: String) throws -> JSONValue? {
    guard let body = requests(method, path).last?.body else { return nil }
    return try JSONDecoder().decode(JSONValue.self, from: body)
  }
}
