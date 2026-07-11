//
//  AssertHTTPRequests.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import HTTPRuntime
@preconcurrency import InlineSnapshotTesting

/// Runs `operation`, then asserts an inline curl snapshot of every request
/// `operation` made against the ambient `HTTPTransportStub.current` — i.e.
/// this must run inside a `.http(stubs:)` scope. Multiple requests made
/// during `operation` render as multiple curl commands joined by a blank
/// line, in call order.
package func assertHTTPRequests<R>(
  fileID: StaticString = #fileID, filePath: StaticString = #filePath,
  function: StaticString = #function,
  line: UInt = #line, column: UInt = #column,
  _ operation: () async throws -> R,
  matches expected: (() -> String)? = nil
) async throws -> R {
  let transport = HTTPTransportStub.current
  let startIndex = await transport.requestCount
  let result = try await operation()
  let requests = await transport.requests(since: startIndex)
  let rendered = requests.map(curlCommand(for:)).joined(separator: "\n\n")
  assertInlineSnapshot(
    of: rendered, as: .lines,
    syntaxDescriptor: InlineSnapshotSyntaxDescriptor(trailingClosureOffset: 1),
    matches: expected,
    fileID: fileID, file: filePath, function: function, line: line, column: column)
  return result
}
