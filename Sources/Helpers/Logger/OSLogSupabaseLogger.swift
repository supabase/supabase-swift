import Foundation

#if canImport(OSLog)
  import OSLog

  /// A SupabaseLogger implementation that logs to OSLog.
  ///
  /// This logger maps Supabase log levels to appropriate OSLog levels:
  /// - `.verbose` → `.info`
  /// - `.debug` → `.debug`
  /// - `.warning` → `.notice`
  /// - `.error` → `.error`
  ///
  /// ## Usage
  ///
  /// ```swift
  /// let supabaseLogger = OSLogSupabaseLogger()
  ///
  /// // Use with Supabase client
  /// let supabase = SupabaseClient(
  ///   supabaseURL: url,
  ///   supabaseKey: key,
  ///   options: .init(global: .init(logger: supabaseLogger))
  /// )
  /// ```
  public struct OSLogSupabaseLogger: SupabaseLogger {
    private let logger: Logger

    /// Creates a new OSLog-based logger with a provided Logger instance.
    ///
    /// - Parameter logger: The OSLog Logger instance to use for logging.
    public init(
      _ logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "Supabase")
    ) {
      self.logger = logger
    }

    public func log(message: SupabaseLogMessage) {
      let logMessage = message.description

      switch message.level {
      case .verbose:
        logger.info("\(logMessage, privacy: .public)")
      case .debug:
        logger.debug("\(logMessage, privacy: .public)")
      case .warning:
        logger.notice("\(logMessage, privacy: .public)")
      case .error:
        logger.error("\(logMessage, privacy: .public)")
      }
    }
  }
#endif
