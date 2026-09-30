//
//  Trace.swift
//  Helpers
//

public import Logging

@inlinable
@discardableResult
package func trace<R: Sendable>(
  using logger: Logging.Logger,
  _ operation: () async throws -> R,
  isolation _: isolated (any Actor)? = #isolation,
  fileID: StaticString = #fileID,
  function: StaticString = #function,
  line: UInt = #line
) async rethrows -> R {
  logger.debug("begin", file: "\(fileID)", function: "\(function)", line: line)
  defer { logger.debug("end", file: "\(fileID)", function: "\(function)", line: line) }

  do {
    return try await operation()
  } catch {
    logger.debug("error: \(error)", file: "\(fileID)", function: "\(function)", line: line)
    throw error
  }
}
