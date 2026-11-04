//
//  LogRecorder.swift
//  TestHelpers
//
//  Created by Guilherme Souza on 04/11/26.
//

import ConcurrencyExtras
package import Logging

/// Collects every line a `Logger` built with ``makeLogger(label:)`` emits, at every level.
package final class LogRecorder: Sendable {
  private let lines = LockIsolated<[String]>([])

  /// Each recorded line: the message followed by its merged metadata as `key=value` pairs.
  package var entries: [String] { lines.value }

  package init() {}

  package func makeLogger(label: String = "test") -> Logging.Logger {
    var logger = Logging.Logger(label: label) { _ in RecordingLogHandler(recorder: self) }
    logger.logLevel = .trace
    return logger
  }

  fileprivate func record(_ line: String) {
    lines.withValue { $0.append(line) }
  }
}

private struct RecordingLogHandler: LogHandler {
  let recorder: LogRecorder
  var metadata: Logging.Logger.Metadata = [:]
  var logLevel: Logging.Logger.Level = .trace

  subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  func log(
    level: Logging.Logger.Level,
    message: Logging.Logger.Message,
    metadata callMetadata: Logging.Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    let merged = metadata.merging(callMetadata ?? [:]) { _, new in new }
    let pairs = merged.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
    recorder.record(([message.description] + pairs).joined(separator: " "))
  }
}
