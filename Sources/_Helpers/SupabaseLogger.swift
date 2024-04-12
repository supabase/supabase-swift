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

public struct SupabaseLogMessage: Codable, CustomStringConvertible, Sendable {
  public let system: String
  public let level: SupabaseLogLevel
  public let message: String
  public let fileID: String
  public let function: String
  public let line: UInt
  public let timestamp: TimeInterval

  @usableFromInline
  init(
    system: String,
    level: SupabaseLogLevel,
    message: String,
    fileID: String,
    function: String,
    line: UInt,
    timestamp: TimeInterval
  ) {
    self.system = system
    self.level = level
    self.message = message
    self.fileID = fileID
    self.function = function
    self.line = line
    self.timestamp = timestamp
  }

  public var description: String {
    let date = iso8601Formatter.string(from: Date(timeIntervalSince1970: timestamp))
    let file = fileID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? fileID
    return "\(date) [\(level)] [\(system)] [\(file).\(function):\(line)] \(message)"
  }
}

private let iso8601Formatter: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter
}()

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
    line: UInt = #line
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
        timestamp: Date().timeIntervalSince1970
      )
    )
  }

  @inlinable
  public func verbose(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    log(.verbose, message: message(), fileID: fileID, function: function, line: line)
  }

  @inlinable
  public func debug(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    log(.debug, message: message(), fileID: fileID, function: function, line: line)
  }

  @inlinable
  public func warning(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    log(.warning, message: message(), fileID: fileID, function: function, line: line)
  }

  @inlinable
  public func error(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    log(.error, message: message(), fileID: fileID, function: function, line: line)
  }
}
