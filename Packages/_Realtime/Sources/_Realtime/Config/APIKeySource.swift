public enum APIKeySource: Sendable {
  case literal(String)
  /// Called on connect and on `token_expired` server signal.
  case dynamic(@Sendable () async throws -> String)
}
