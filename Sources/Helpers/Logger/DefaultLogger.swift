//
//  DefaultLogger.swift
//  Helpers
//

public import Logging

/// Builds the default `Logging.Logger` used when a module's `logger:` parameter is omitted.
///
/// The default is silent in every build configuration: it uses `SwiftLogNoOpLogHandler`, so no
/// line reaches any destination. Its `logLevel` is `.critical`, and `Logger.log(level:...)`
/// checks `self.logLevel <= level` before it evaluates the message autoclosure, so the SDK's own
/// call sites, which never log at `.critical`, cost no string interpolation.
///
/// To receive the SDK's log lines, pass your own configured `Logging.Logger`.
@usableFromInline
package func supabaseDefaultLogger(label: String) -> Logging.Logger {
  var logger = Logging.Logger(label: label, factory: { _ in SwiftLogNoOpLogHandler() })
  logger.logLevel = .critical
  return logger
}
