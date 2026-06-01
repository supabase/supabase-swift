import Foundation

public protocol RealtimeLogger: Sendable {
  func log(_ event: LogEvent)
}

public struct LogEvent: Sendable {
  public let level: LogLevel
  public let category: LogCategory
  public let message: String
  public let metadata: [String: String]
  public let timestamp: Date

  public init(
    level: LogLevel,
    category: LogCategory,
    message: String,
    metadata: [String: String] = [:],
    timestamp: Date = Date()
  ) {
    self.level = level
    self.category = category
    self.message = message
    self.metadata = metadata
    self.timestamp = timestamp
  }
}

public enum LogLevel: Sendable { case debug, info, warn, error }
public enum LogCategory: Sendable { case connection, channel, broadcast, presence, postgres }
