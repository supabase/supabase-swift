import Foundation

struct ImplicitTokens: Sendable, Hashable {
  var accessToken: String
  var refreshToken: String
  var tokenType: String
  var expiresIn: Duration
  var expiresAt: Date?
  var providerToken: String?
  var providerRefreshToken: String?
}

/// What a URL opened in the app asks the client to do, decided by the URL's contents alone.
enum AuthRedirect: Sendable, Equatable {
  case code(String)
  case implicit(ImplicitTokens, type: EmailOTPType?)
  case error(AuthError)
  case emailChangePending(message: String)

  static func parse(_ url: URL) -> AuthRedirect? {
    let items = items(of: url)

    if items["error"] != nil || items["error_code"] != nil || items["error_description"] != nil {
      let message = items["error_description"] ?? items["error"] ?? "The redirect reports an error."
      let code = items["error_code"].map(AuthError.Code.init(rawValue:))
      return .error(.oauthFlowFailed(message, code: code))
    }

    if let message = items["message"], items["sb"] != nil {
      return .emailChangePending(message: message)
    }

    if let code = items["code"] {
      return .code(code)
    }

    if let accessToken = items["access_token"] {
      guard
        let refreshToken = items["refresh_token"],
        let tokenType = items["token_type"],
        let expiresIn = items["expires_in"].flatMap(TimeInterval.init)
          .flatMap(Duration.init(validSeconds:))
      else {
        return .error(
          .oauthFlowFailed(
            "The redirect has an access token but no refresh token, token type, or expiry."))
      }
      let tokens = ImplicitTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        tokenType: tokenType,
        expiresIn: expiresIn,
        expiresAt: items["expires_at"].flatMap(TimeInterval.init).map(
          Date.init(timeIntervalSince1970:)),
        providerToken: items["provider_token"],
        providerRefreshToken: items["provider_refresh_token"]
      )
      return .implicit(tokens, type: items["type"].map(EmailOTPType.init(rawValue:)))
    }

    if items["sb"] != nil {
      return .error(.oauthFlowFailed("Supabase redirect without a result"))
    }

    return nil
  }

  /// The key that the client deduplicates the redirect by, or `nil` when it is not deduplicated.
  var deduplicationKey: String? {
    switch self {
    case .code(let code): code
    case .implicit(let tokens, _): tokens.accessToken
    case .error, .emailChangePending: nil
    }
  }

  /// Whether `url` opens `callback`: the same scheme, host, port, and path. Scheme and host
  /// compare without case, and a trailing slash on the path is ignored. The query and the fragment
  /// are ignored, because the server adds its result there.
  static func url(_ url: URL, reaches callback: URL) -> Bool {
    guard
      let lhs = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let rhs = URLComponents(url: callback, resolvingAgainstBaseURL: false)
    else { return false }
    let scheme = lhs.scheme?.lowercased()
    return scheme == rhs.scheme?.lowercased()
      && lhs.host?.lowercased() == rhs.host?.lowercased()
      && effectivePort(lhs.port, scheme: scheme) == effectivePort(rhs.port, scheme: scheme)
      && normalizedPath(lhs.path) == normalizedPath(rhs.path)
  }

  /// `nil` for the default port of the scheme, so `https://a.com:443` matches `https://a.com`.
  private static func effectivePort(_ port: Int?, scheme: String?) -> Int? {
    switch (scheme, port) {
    case ("http", 80), ("https", 443): nil
    default: port
    }
  }

  private static func normalizedPath(_ path: String) -> String {
    var path = Substring(path)
    while path.hasSuffix("/") { path = path.dropLast() }
    return String(path)
  }

  static func == (lhs: AuthRedirect, rhs: AuthRedirect) -> Bool {
    switch (lhs, rhs) {
    case (.code(let a), .code(let b)): a == b
    case (.implicit(let a, let aType), .implicit(let b, let bType)): a == b && aType == bType
    case (.emailChangePending(let a), .emailChangePending(let b)): a == b
    case (.error(let a), .error(let b)):
      a.kind == b.kind && a.message == b.message && a.code == b.code
    default: false
    }
  }

  /// Reads the query, then the fragment. Empty values and keys without `=` are kept, and a
  /// fragment key overwrites the same query key.
  private static func items(of url: URL) -> [String: String] {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    var result: [String: String] = [:]
    for raw in [components?.percentEncodedQuery, components?.percentEncodedFragment] {
      for pair in (raw ?? "").split(separator: "&", omittingEmptySubsequences: true) {
        let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        result[decode(parts[0])] = parts.count > 1 ? decode(parts[1]) : ""
      }
    }
    return result
  }

  private static func decode(_ part: Substring) -> String {
    let spaced = part.replacingOccurrences(of: "+", with: " ")
    return spaced.removingPercentEncoding ?? spaced
  }
}
