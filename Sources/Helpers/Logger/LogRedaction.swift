import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Removes secrets from what ``LoggerInterceptor`` writes to the log.
enum LogRedaction {
  static let placeholder = "<redacted>"

  /// The keys whose values never appear in a log, in lowercase without separators. Matched as
  /// `refresh_token`, `refreshToken`, and `refreshtoken` alike.
  static let sensitiveKeys: Set<String> = [
    "accesstoken", "refreshtoken", "idtoken", "providertoken", "providerrefreshtoken",
    "codeverifier", "authcode", "verifier", "tokenhash", "hashedtoken", "emailotp", "otp",
    "password",
    "clientsecret", "secret", "token", "apikey",
  ]

  /// JSON keys that hold a signed URL or a sign-in link.
  static let linkKeys: Set<String> = ["actionlink", "signedurl", "url"]

  /// Whether a JSON body redacts the value of `key`: a sensitive key or a link key.
  static func isSensitive(jsonKey key: String) -> Bool {
    let key = key.lowercased().filter { $0 != "_" && $0 != "-" }
    return sensitiveKeys.contains(key) || linkKeys.contains(key)
  }

  /// `object`, a value from `JSONSerialization`, with each sensitive value replaced.
  static func redactingSecrets(in object: Any) -> Any {
    if let dictionary = object as? [String: Any] {
      return dictionary.reduce(into: [String: Any]()) { result, entry in
        result[entry.key] =
          isSensitive(jsonKey: entry.key) ? placeholder : redactingSecrets(in: entry.value)
      }
    }
    if let array = object as? [Any] {
      return array.map(redactingSecrets(in:))
    }
    return object
  }

  /// The URL without its query and fragment, which can hold a signed token or a filter value.
  static func loggable(_ url: URL?) -> String {
    guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return ""
    }
    components.query = nil
    components.fragment = nil
    return components.string?.removingPercentEncoding ?? ""
  }

  /// A description of `error` that leaves out the failing URL of a URL loading error.
  static func summary(of error: any Error) -> String {
    switch error {
    case let error as URLError:
      return "\(NSURLErrorDomain) \(error.errorCode)"
    case let error as NSError where error.domain == NSURLErrorDomain:
      return "\(error.domain) \(error.code)"
    default:
      return String(describing: error)
    }
  }
}
