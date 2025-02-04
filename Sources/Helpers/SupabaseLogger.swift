import Foundation

public enum SupabaseLogLevel: Int, Codable, CustomStringConvertible, Sendable {
  case verbose
  case debug
  case warning
  case error

  public var description: String {
    switch self {
    case .verbose: "verbose"
    case .debug: "debug"
    case .warning: "warning"
    case .error: "error"
    }
  }
}

@usableFromInline
package enum SupabaseLoggerTaskLocal {
  @TaskLocal
  @usableFromInline
  package static var additionalContext: JSONObject = [:]
}

public struct SupabaseLogMessage: Codable, CustomStringConvertible, Sendable {
  public let system: String
  public let level: SupabaseLogLevel
  public let message: String
  public let fileID: String
  public let function: String
  public let line: UInt
  public let timestamp: TimeInterval
  public var additionalContext: JSONObject

  @usableFromInline
  init(
    system: String,
    level: SupabaseLogLevel,
    message: String,
    fileID: String,
    function: String,
    line: UInt,
    timestamp: TimeInterval,
    additionalContext: JSONObject
  ) {
    self.system = system
    self.level = level
    self.message = message
    self.fileID = fileID
    self.function = function
    self.line = line
    self.timestamp = timestamp
    self.additionalContext = additionalContext
  }

  public var description: String {
    let date = ISO8601DateFormatter.iso8601.value.string(
      from: Date(timeIntervalSince1970: timestamp))
    let file = fileID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? fileID
    var description = "\(date) [\(level)] [\(system)] [\(file).\(function):\(line)] \(message)"
    if !additionalContext.isEmpty {
      description += "\ncontext: \(additionalContext.description)"
    }
    return description
  }
}

public protocol SupabaseLogger: Sendable {
  func log(message: SupabaseLogMessage)
}

extension SupabaseLogger {
  @inlinable
  public func log(
    _ level: SupabaseLogLevel,
    message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line,
    additionalContext: JSONObject = [:]
  ) {
    let system = "\(fileID)".split(separator: "/").first ?? ""

    log(
      message: SupabaseLogMessage(
        system: "\(system)",
        level: level,
        message: message(),
        fileID: "\(fileID)",
        function: "\(function)",
        line: line,
        timestamp: Date().timeIntervalSince1970,
        additionalContext: additionalContext.merging(
          SupabaseLoggerTaskLocal.additionalContext,
          uniquingKeysWith: { _, new in new }
        )
      )
    )
  }

  @inlinable
  public func verbose(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line,
    additionalContext: JSONObject = [:]
  ) {
    log(
      .verbose,
      message: message(),
      fileID: fileID,
      function: function,
      line: line,
      additionalContext: additionalContext
    )
  }

  @inlinable
  public func debug(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line,
    additionalContext: JSONObject = [:]
  ) {
    log(
      .debug,
      message: message(),
      fileID: fileID,
      function: function,
      line: line,
      additionalContext: additionalContext
    )
  }

  @inlinable
  public func warning(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line,
    additionalContext: JSONObject = [:]
  ) {
    log(
      .warning,
      message: message(),
      fileID: fileID,
      function: function,
      line: line,
      additionalContext: additionalContext
    )
  }

  @inlinable
  public func error(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line,
    additionalContext: JSONObject = [:]
  ) {
    log(
      .error,
      message: message(),
      fileID: fileID,
      function: function,
      line: line,
      additionalContext: additionalContext
    )
  }
}

#if compiler(>=6.0)
  @inlinable
  @discardableResult
  package func trace<R: Sendable>(
    using logger: (any SupabaseLogger)?,
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
    using logger: (any SupabaseLogger)?,
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
