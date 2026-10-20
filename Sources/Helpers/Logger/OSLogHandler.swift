//
//  OSLogHandler.swift
//  Helpers
//

import Foundation
import Logging

#if canImport(OSLog)
  import OSLog

  struct OSLogHandler: LogHandler {
    private let osLogger: os.Logger

    var metadata: Logging.Logger.Metadata = [:]

    var logLevel: Logging.Logger.Level = .trace

    init(label: String, subsystem: String = Bundle.main.bundleIdentifier ?? "") {
      osLogger = os.Logger(subsystem: subsystem, category: label)
    }

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
      get { metadata[key] }
      set { metadata[key] = newValue }
    }

    func log(
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
