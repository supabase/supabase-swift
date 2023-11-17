import Foundation

public struct SupabaseLogger: Sendable {
  public enum Level: Int, Codable, CustomStringConvertible, Sendable {
    case debug
    case warning
    case error

    public var description: String {
      switch self {
      case .debug:
        "debug"
      case .warning:
        "warning"
      case .error:
        "error"
      }
    }
  }

  struct Message: Codable, CustomStringConvertible {
    let system: String
    let level: Level
    let message: String
    let fileID: String
    let function: String
    let line: UInt
    let timestamp: TimeInterval

    var description: String {
      let date = iso8601Formatter.string(from: Date(timeIntervalSince1970: timestamp))
      let file = self.fileID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? fileID
      return "\(date) [\(level)] [\(system)] [\(file).\(function):\(line)] \(message)"
    }
  }

  let system: String
  let minLevel: Level

  public init(system: String, minLevel: Level = .debug) {
    self.system = system
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

    let message = Message(
      system: system,
      level: level,
      message: message(),
      fileID: "\(fileID)",
      function: "\(function)",
      line: line,
      timestamp: Date().timeIntervalSince1970
    )

    print(message)
  }

  private func shouldLog(_ level: Level) -> Bool {
    level.rawValue >= minLevel.rawValue
  }
}

private let iso8601Formatter: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter
}()
