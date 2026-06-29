//
//  RealtimeLogger.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation

// MARK: - RealtimeLogger

/// A sink that receives structured log events from the Realtime SDK.
///
/// Implement this protocol to route events to any destination — os.Logger, file,
/// remote telemetry, etc. Implementations must be `Sendable` and must never throw.
public protocol RealtimeLogger: Sendable {
  func log(_ event: LogEvent)
}

// MARK: - LogEvent

/// A structured log event emitted by the Realtime SDK.
///
/// `metadata` carries auxiliary key-value pairs. Numeric metrics (latency, attempt
/// counters) are encoded as decimal string values under well-known keys:
/// - `"heartbeat.rtt_ms"` — heartbeat round-trip time in milliseconds.
/// - `"reconnect.attempt"` — reconnect attempt number (1-based).
/// - `"broadcast.ack_latency_ms"` — acked broadcast round-trip time in milliseconds.
public struct LogEvent: Sendable {
  /// Severity level of the event.
  public let level: LogLevel
  /// Functional category the event belongs to.
  public let category: Category
  /// Human-readable description of what happened.
  public let message: String
  /// Auxiliary key-value pairs — numeric metrics are encoded as decimal strings.
  public let metadata: [String: String]
  /// Wall-clock time the event was created.
  public let timestamp: Date

  public init(
    level: LogLevel,
    category: Category,
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

// MARK: - LogLevel

/// Severity levels mirroring conventional logging frameworks.
public enum LogLevel: Sendable {
  case debug
  case info
  case warn
  case error
}

// MARK: - Category

/// Functional category of a log event within the Realtime SDK.
public enum Category: Sendable {
  /// Events related to the WebSocket connection lifecycle.
  case connection
  /// Events related to channel join/leave lifecycle.
  case channel
  /// Events related to broadcast send/receive.
  case broadcast
  /// Events related to presence track/untrack.
  case presence
  /// Events related to postgres_changes subscriptions.
  case postgres
}

// MARK: - OSLogLogger

#if canImport(OSLog)
  import OSLog

  /// A `RealtimeLogger` that forwards events to `os.Logger` (Apple unified logging).
  ///
  /// Available on macOS 11+, iOS 14+, tvOS 14+, watchOS 7+, visionOS 1+.
  @available(macOS 11, iOS 14, tvOS 14, watchOS 7, visionOS 1, *)
  public struct OSLogLogger: RealtimeLogger {
    private let logger: Logger

    /// Creates an `OSLogLogger` using the given subsystem and category.
    ///
    /// - Parameters:
    ///   - subsystem: Reverse-DNS identifier for the logger (e.g. `"io.supabase.realtime"`).
    ///   - category: OSLog category string. Defaults to `"RealtimeV3"`.
    public init(subsystem: String = "io.supabase.realtime", category: String = "RealtimeV3") {
      self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func log(_ event: LogEvent) {
      let message = Self.format(event)
      switch event.level {
      case .debug:
        logger.debug("\(message, privacy: .public)")
      case .info:
        logger.info("\(message, privacy: .public)")
      case .warn:
        logger.warning("\(message, privacy: .public)")
      case .error:
        logger.error("\(message, privacy: .public)")
      }
    }

    private static func format(_ event: LogEvent) -> String {
      var parts = ["[\(event.category)] \(event.message)"]
      if !event.metadata.isEmpty {
        let metaString = event.metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(
          separator: " ")
        parts.append(metaString)
      }
      return parts.joined(separator: " | ")
    }
  }
#endif

// MARK: - StdoutLogger

/// A `RealtimeLogger` that prints formatted log lines to standard output.
///
/// Output format: `[ISO8601 timestamp] [LEVEL] [category] message | key=value ...`
public struct StdoutLogger: RealtimeLogger {
  public init() {}

  public func log(_ event: LogEvent) {
    let timestamp = Self.formatDate(event.timestamp)
    var line =
      "\(timestamp) [\(Self.levelLabel(event.level))] [\(Self.categoryLabel(event.category))] \(event.message)"
    if !event.metadata.isEmpty {
      let metaString = event.metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(
        separator: " ")
      line += " | \(metaString)"
    }
    print(line)
  }

  private static func formatDate(_ date: Date) -> String {
    // Use a thread-local formatter to avoid Sendable issues with ISO8601DateFormatter.
    // The format is ISO 8601 with fractional seconds.
    let calendar = Calendar(identifier: .gregorian)
    let comps = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: date
    )
    let ms = Int((date.timeIntervalSince1970 - floor(date.timeIntervalSince1970)) * 1000)
    let year = comps.year ?? 0
    let month = comps.month ?? 0
    let day = comps.day ?? 0
    let hour = comps.hour ?? 0
    let minute = comps.minute ?? 0
    let second = comps.second ?? 0
    return String(
      format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
      year, month, day, hour, minute, second, ms
    )
  }

  private static func levelLabel(_ level: LogLevel) -> String {
    switch level {
    case .debug: return "DEBUG"
    case .info: return "INFO"
    case .warn: return "WARN"
    case .error: return "ERROR"
    }
  }

  private static func categoryLabel(_ category: Category) -> String {
    switch category {
    case .connection: return "connection"
    case .channel: return "channel"
    case .broadcast: return "broadcast"
    case .presence: return "presence"
    case .postgres: return "postgres"
    }
  }
}
