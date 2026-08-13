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

    /// Defaults to `.trace`, so every level is forwarded to OSLog by default — matching the old
    /// `OSLogSupabaseLogger`, which had no threshold at all and let Console.app's own UI handle
    /// level-based filtering on the viewing side. Set this to raise the threshold instead.
    public var logLevel: Logging.Logger.Level = .trace

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
      let text = renderedMessage(
        message: message,
        metadata: metadata,
        file: file,
        function: function,
        line: line
      )
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

    /// Renders `message` together with the merged metadata (`self.metadata` merged with the
    /// per-call `metadata`, per-call taking precedence on key conflicts) and the source location,
    /// mirroring the old `SupabaseLogMessage.description` (message + `[file.function:line]` +
    /// `context: <additionalContext>` when non-empty). Exposed at `internal` visibility so tests
    /// can verify the rendered output without going through OSLog itself.
    func renderedMessage(
      message: Logging.Logger.Message,
      metadata: Logging.Logger.Metadata?,
      file: String,
      function: String,
      line: UInt
    ) -> String {
      var mergedMetadata = self.metadata
      if let metadata {
        mergedMetadata.merge(metadata) { _, new in new }
      }

      let fileName = file.split(separator: "/").last.map(String.init) ?? file
      var rendered = "\(message) [\(fileName).\(function):\(line)]"

      if !mergedMetadata.isEmpty {
        let context =
          mergedMetadata
          .sorted { $0.key < $1.key }
          .map { "\($0.key): \($0.value)" }
          .joined(separator: ", ")
        rendered += " context: \(context)"
      }

      return rendered
    }
  }
#endif
