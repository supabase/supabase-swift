//
//  RealtimeServerLogLevel.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

/// How much the Realtime server logs about this client's socket, in the project's Realtime logs.
///
/// Sent as the `log_level` query parameter of the WebSocket URL.
public struct RealtimeServerLogLevel: RawRepresentable, Sendable, Hashable,
  ExpressibleByStringLiteral
{
  /// The value the server receives.
  public let rawValue: String

  /// Creates a level from the server's value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a level from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Logs everything, including each message.
  public static let info: RealtimeServerLogLevel = "info"
  /// Logs warnings and errors.
  public static let warning: RealtimeServerLogLevel = "warning"
  /// Logs errors only.
  public static let error: RealtimeServerLogLevel = "error"
}
