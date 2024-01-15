import Foundation

public struct SupabaseLogger: Sendable {
  let system: String
  let minLevel: Level
  let handler: SupabaseLogHandler

  public init(system: String, handler: SupabaseLogHandler, minLevel: Level = .debug) {
    self.system = system
    self.handler = handler
    self.minLevel = minLevel
  }

  public func log(
    _ level: Level,
    message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    guard shouldLog(level) else { return }

    let entry = Entry(
      system: system,
      level: level,
      message: message(),
      fileID: "\(fileID)",
      function: "\(function)",
      line: line,
      timestamp: Date().timeIntervalSince1970
    )

    handler.didLog(entry)
  }

  private func shouldLog(_ level: Level) -> Bool {
    level.rawValue >= minLevel.rawValue
  }

  public func debug(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    log(.debug, message: message(), fileID: fileID, function: function, line: line)
  }

  public func warning(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    log(.warning, message: message(), fileID: fileID, function: function, line: line)
  }

  public func error(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    log(.error, message: message(), fileID: fileID, function: function, line: line)
  }
}
