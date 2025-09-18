import Foundation
import Logging

/// A logging interface that uses swift-log for standardized logging across the Swift ecosystem.
///
/// This replaces the previous SupabaseLogger implementation with a more standardized approach
/// using the swift-log library, which provides better integration with Swift ecosystem tools.
public typealias SupabaseLogger = Logger

/// Extension to provide convenient logging methods that maintain compatibility with existing code.
extension Logger {
  /// Log a verbose message.
  ///
  /// - Parameters:
  ///   - message: The message to log.
  ///   - fileID: The file ID where the log was called (defaults to #fileID).
  ///   - function: The function where the log was called (defaults to #function).
  ///   - line: The line number where the log was called (defaults to #line).
  ///   - additionalContext: Additional context to include in the log.
  @inlinable
  public func verbose(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line,
    additionalContext: [String: String] = [:]
  ) {
    var logger = self
    for (key, value) in additionalContext {
      logger[metadataKey: key] = "\(value)"
    }
    logger.trace("\(message())", file: "\(fileID)", function: "\(function)", line: line)
  }

  /// Log a debug message.
  ///
  /// - Parameters:
  ///   - message: The message to log.
  ///   - fileID: The file ID where the log was called (defaults to #fileID).
  ///   - function: The function where the log was called (defaults to #function).
  ///   - line: The line number where the log was called (defaults to #line).
  ///   - additionalContext: Additional context to include in the log.
  @inlinable
  public func debug(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line,
    additionalContext: [String: String] = [:]
  ) {
    var logger = self
    for (key, value) in additionalContext {
      logger[metadataKey: key] = "\(value)"
    }
    logger.debug("\(message())", file: "\(fileID)", function: "\(function)", line: line)
  }

  /// Log a warning message.
  ///
  /// - Parameters:
  ///   - message: The message to log.
  ///   - fileID: The file ID where the log was called (defaults to #fileID).
  ///   - function: The function where the log was called (defaults to #function).
  ///   - line: The line number where the log was called (defaults to #line).
  ///   - additionalContext: Additional context to include in the log.
  @inlinable
  public func warning(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line,
    additionalContext: [String: String] = [:]
  ) {
    var logger = self
    for (key, value) in additionalContext {
      logger[metadataKey: key] = "\(value)"
    }
    logger.warning("\(message())", file: "\(fileID)", function: "\(function)", line: line)
  }

  /// Log an error message.
  ///
  /// - Parameters:
  ///   - message: The message to log.
  ///   - fileID: The file ID where the log was called (defaults to #fileID).
  ///   - function: The function where the log was called (defaults to #function).
  ///   - line: The line number where the log was called (defaults to #line).
  ///   - additionalContext: Additional context to include in the log.
  @inlinable
  public func error(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line,
    additionalContext: [String: String] = [:]
  ) {
    var logger = self
    for (key, value) in additionalContext {
      logger[metadataKey: key] = "\(value)"
    }
    logger.error("\(message())", file: "\(fileID)", function: "\(function)", line: line)
  }
}

#if compiler(>=6.0)
  @inlinable
  @discardableResult
  package func trace<R: Sendable>(
    using logger: SupabaseLogger?,
    _ operation: () async throws -> R,
    isolation _: isolated (any Actor)? = #isolation,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line
  ) async rethrows -> R {
    logger?.debug("begin", fileID: fileID, function: function, line: line)
    defer { logger?.debug("end", fileID: fileID, function: function, line: line) }

    do {
      return try await operation()
    } catch {
      logger?.debug("error: \(error)", fileID: fileID, function: function, line: line)
      throw error
    }
  }
#else
  @_unsafeInheritExecutor
  @inlinable
  @discardableResult
  package func trace<R: Sendable>(
    using logger: SupabaseLogger?,
    _ operation: () async throws -> R,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line
  ) async rethrows -> R {
    logger?.debug("begin", fileID: fileID, function: function, line: line)
    defer { logger?.debug("end", fileID: fileID, function: function, line: line) }

    do {
      return try await operation()
    } catch {
      logger?.debug("error: \(error)", fileID: fileID, function: function, line: line)
      throw error
    }
  }
#endif

