//
//  DefaultLogger.swift
//  Helpers
//

package import Logging

/// Builds the default `Logging.Logger` used when a module's `logger:` parameter is omitted.
///
/// - In debug builds, returns a logger at `.warning` level, so warnings and errors are visible
///   during development without any manual setup.
/// - In release builds, returns a logger backed by `SwiftLogNoOpLogHandler` with `logLevel`
///   raised to `.critical`. `Logger.log(level:...)` checks `self.logLevel <= level` before
///   evaluating the message autoclosure, so this is genuinely zero-overhead: no string
///   interpolation happens for calls below `.critical`, which none of this package's own log
///   call sites use.
///
/// Callers who want different behavior pass their own configured `Logging.Logger` instead of
/// relying on this default.
package func supabaseDefaultLogger(label: String) -> Logging.Logger {
  #if DEBUG
    var logger = Logging.Logger(label: label)
    logger.logLevel = .warning
    return logger
  #else
    var logger = Logging.Logger(label: label, factory: { _ in SwiftLogNoOpLogHandler() })
    logger.logLevel = .critical
    return logger
  #endif
}
