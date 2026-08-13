//
//  OSLogHandler.swift
//  Helpers
//

public import Foundation
public import Logging

#if canImport(OSLog)
  import OSLog

  /// A `Logging.LogHandler` backed by `OSLog`, giving OSLog/Console.app integration to callers
  /// who want it explicitly — construct it and pass the resulting `Logger` in, no process-wide
  /// `LoggingSystem.bootstrap` required:
  ///
  /// ```swift
  /// let logger = Logging.Logger(label: "io.supabase.auth") { OSLogHandler(label: $0) }
  /// ```
  public struct OSLogHandler: LogHandler {
    private let osLogger: os.Logger

    public var metadata: Logging.Logger.Metadata = [:]
    public var logLevel: Logging.Logger.Level = .info

    /// - Parameters:
    ///   - label: Used as the OSLog category.
    ///   - subsystem: The OSLog subsystem. Defaults to the host app's bundle identifier.
    public init(label: String, subsystem: String = Bundle.main.bundleIdentifier ?? "") {
      osLogger = os.Logger(subsystem: subsystem, category: label)
    }

    public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
      get { metadata[key] }
      set { metadata[key] = newValue }
    }

    public func log(
      level: Logging.Logger.Level,
      message: Logging.Logger.Message,
      metadata: Logging.Logger.Metadata?,
      source: String,
      file: String,
      function: String,
      line: UInt
    ) {
      let text = "\(message)"
      switch level {
      case .trace, .debug:
        osLogger.debug("\(text, privacy: .public)")
      case .info:
        osLogger.info("\(text, privacy: .public)")
      case .notice, .warning:
        osLogger.notice("\(text, privacy: .public)")
      case .error:
        osLogger.error("\(text, privacy: .public)")
      case .critical:
        osLogger.fault("\(text, privacy: .public)")
      }
    }
  }
#endif
