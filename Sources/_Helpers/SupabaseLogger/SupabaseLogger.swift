import Foundation

public struct SupabaseLoggingConfiguration: Sendable {
  public let disabled: Bool
  public let minLevel: SupabaseLogLevel
  public let logFile: URL

  public init(
    disabled: Bool = true,
    minLevel: SupabaseLogLevel = .debug,
    logFile: URL = Self.defaultLogFileLocationURL
  ) {
    self.disabled = disabled
    self.minLevel = minLevel
    self.logFile = logFile
  }

  public static let defaultLogFileLocationURL = try! FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
  ).appendingPathComponent("supabase-swift.log")
}

@_spi(Internal)
public struct SupabaseLogger: Sendable {
  let system: String
  let configuration: SupabaseLoggingConfiguration
  let handler: SupabaseLogHandler

  public init(system: String, configuration: SupabaseLoggingConfiguration) {
    self.system = system
    handler = DefaultSupabaseLogHandler.instance(for: configuration.logFile)
    self.configuration = configuration
  }

  public func log(
    _ level: SupabaseLogLevel,
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

  private func shouldLog(_ level: SupabaseLogLevel) -> Bool {
    !configuration.disabled && level.rawValue >= configuration.minLevel.rawValue
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
