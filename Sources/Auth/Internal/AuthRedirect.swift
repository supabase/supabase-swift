import Foundation

struct ImplicitTokens: Sendable, Hashable {
  var accessToken: String
  var refreshToken: String
  var tokenType: String
  var expiresIn: TimeInterval
  var expiresAt: TimeInterval?
  var providerToken: String?
  var providerRefreshToken: String?
}

/// What a URL opened in the app asks the client to do, decided by the URL's contents alone.
enum AuthRedirect: Sendable, Equatable {
  case code(String, flowID: UUID?)
  case implicit(ImplicitTokens, type: EmailOTPType?)
  case error(AuthError)
  case emailChangePending(message: String)

  /// The deduplication key: the code or the access token. `nil` for other cases.
  var credential: String? {
    switch self {
    case .code(let code, _): code
    case .implicit(let tokens, _): tokens.accessToken
    case .error, .emailChangePending: nil
    }
  }

  static func parse(_ url: URL) -> AuthRedirect? {
    let items = items(of: url)

    if items["error"] != nil || items["error_code"] != nil || items["error_description"] != nil {
      let message = items["error_description"] ?? items["error"] ?? "The redirect reports an error."
      let errorCode = items["error_code"].map { ErrorCode($0) } ?? .unknown
      return .error(.oauthFlowFailed(message, errorCode: errorCode))
    }

    if let message = items["message"] {
      return .emailChangePending(message: message)
    }

    if let code = items["code"] {
      return .code(code, flowID: items["sb_flow_id"].flatMap(UUID.init(uuidString:)))
    }

    if let accessToken = items["access_token"] {
      guard
        let refreshToken = items["refresh_token"],
        let tokenType = items["token_type"],
        let expiresIn = items["expires_in"].flatMap(TimeInterval.init)
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
        expiresAt: items["expires_at"].flatMap(TimeInterval.init),
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

  static func == (lhs: AuthRedirect, rhs: AuthRedirect) -> Bool {
    switch (lhs, rhs) {
    case (.code(let a, let aID), .code(let b, let bID)): a == b && aID == bID
    case (.implicit(let a, let aType), .implicit(let b, let bType)): a == b && aType == bType
    case (.emailChangePending(let a), .emailChangePending(let b)): a == b
    case (.error(let a), .error(let b)):
      a.kind == b.kind && a.message == b.message && a.errorCode == b.errorCode
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
