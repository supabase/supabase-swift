extension AuthClient {
  /// When an ``AuthClient`` refreshes the session on its own.
  ///
  /// The policy covers only the refreshes the client starts by itself. A refresh you ask for with
  /// ``AuthClient/refreshSession(refreshToken:)`` or ``AuthClient/refreshSessionIfNeeded()``
  /// runs under every policy.
  public enum AutoRefreshPolicy: Sendable, Hashable {
    /// The client refreshes the session 90 seconds before its access token expires, and
    /// ``AuthClient/session`` refreshes an expired session before it returns.
    ///
    /// Auto refresh starts when the client is created. Use ``AuthClient/stopAutoRefresh()`` and
    /// ``AuthClient/startAutoRefresh()`` to pause and resume it.
    case automatic

    /// ``AuthClient/session`` refreshes an expired session before it returns, and a
    /// `SupabaseClient` data request that the server rejects for a stale token refreshes it once.
    /// The client does not refresh it ahead of time. Call
    /// ``AuthClient/refreshSessionIfNeeded()``, for example from a `BGAppRefreshTask`, to do that.
    case manual

    /// The client never refreshes the session on its own. ``AuthClient/session`` returns the
    /// stored session until it expires, then throws an ``AuthError`` of kind
    /// ``AuthError/Kind-swift.struct/refreshDisabled``.
    ///
    /// Use it in an app extension or another process that shares storage with the main app and
    /// must not refresh. Two processes that refresh the same refresh token race, and the server
    /// can then revoke the session. The client reads storage once, when it is created, so a
    /// long-lived process does not see a session the main app refreshes later.
    case disabled
  }
}
