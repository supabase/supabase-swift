import Foundation
package import Logging

/// Removes secrets from a log line before swift-log passes it to a handler.
///
/// `OSLogHandler` prints the rendered text as `.public`, so a secret has to be gone before the
/// handler sees it. The rules are a backstop: the typed descriptions of `Session`, `AuthChange`,
/// and `PendingFlowRecord` keep tokens out of an interpolated value in the first place.
package enum LogRedaction {
  package static let placeholder = "<redacted>"

  /// The keys whose values never appear in a log, in lowercase without separators. Matched as
  /// `refresh_token`, `refreshToken`, and `refreshtoken` alike.
  package static let sensitiveKeys: Set<String> = [
    "accesstoken", "refreshtoken", "idtoken", "providertoken", "providerrefreshtoken",
    "codeverifier", "authcode", "verifier", "tokenhash", "hashedtoken", "emailotp", "otp",
    "password",
    "clientsecret", "secret", "token", "apikey",
  ]

  package static func redact(_ text: String) -> String {
    var result = text
    if result.contains("://") || result.contains(#":\/"#) {
      result.replace(urlWithQueryOrFragment) { String($0.output.1) }
    }
    result.replace(sensitivePair) { "\($0.output.1)\(placeholder)" }
    if result.contains("eyJ") {
      result.replace(jwt) { _ in placeholder }
    }
    if result.contains("sb_secret_") {
      result.replace(secretAPIKey) { _ in placeholder }
    }
    return result
  }

  /// JSON keys that hold a signed URL or a sign-in link. A response body redacts them on top of
  /// ``sensitiveKeys``; a log message does not, because a URL in text loses only its query.
  package static let linkKeys: Set<String> = ["actionlink", "signedurl", "url"]

  /// A description of `error` for an `.error` line that leaves out what is known to leak.
  ///
  /// A URL loading error keeps only its domain and code: its description holds the failing URL.
  /// A coding error keeps its case and coding path: its description can echo the value. Any
  /// other error keeps its description, which the redacting handler cleans.
  package static func summary(of error: any Error) -> String {
    switch error {
    case let error as DecodingError:
      return summary(of: error)
    case let error as EncodingError:
      guard case .invalidValue(_, let context) = error else { return "EncodingError" }
      return "EncodingError.invalidValue at '\(path(of: context))'"
    case let error as URLError:
      return "\(NSURLErrorDomain) \(error.errorCode)"
    case let error as NSError where error.domain == NSURLErrorDomain:
      return "\(error.domain) \(error.code)"
    default:
      return String(describing: error)
    }
  }

  private static func path(of context: DecodingError.Context?) -> String {
    context?.codingPath.map(\.stringValue).joined(separator: ".") ?? ""
  }

  private static func path(of context: EncodingError.Context) -> String {
    context.codingPath.map(\.stringValue).joined(separator: ".")
  }

  private static func summary(of error: DecodingError) -> String {
    let (kind, context): (String, DecodingError.Context?) =
      switch error {
      case .typeMismatch(_, let context): ("typeMismatch", context)
      case .valueNotFound(_, let context): ("valueNotFound", context)
      case .keyNotFound(let key, let context): ("keyNotFound '\(key.stringValue)'", context)
      case .dataCorrupted(let context): ("dataCorrupted", context)
      @unknown default: ("unknown", nil)
      }
    return "DecodingError.\(kind) at '\(path(of: context))'"
  }

  package static func isSensitive(key: String) -> Bool {
    sensitiveKeys.contains(normalized(key))
  }

  /// Whether a response body redacts the value of `key`: a sensitive key or a link key.
  package static func isSensitive(jsonKey key: String) -> Bool {
    let key = normalized(key)
    return sensitiveKeys.contains(key) || linkKeys.contains(key)
  }

  private static func normalized(_ key: String) -> String {
    key.lowercased().filter { $0 != "_" && $0 != "-" }
  }

  package static func redact(_ metadata: Logging.Logger.Metadata) -> Logging.Logger.Metadata {
    metadata.reduce(into: [:]) { $0[$1.key] = redact($1.value, forKey: $1.key) }
  }

  package static func redact(
    _ value: Logging.Logger.MetadataValue, forKey key: String
  ) -> Logging.Logger.MetadataValue {
    if isSensitive(key: key) { return .string(placeholder) }
    switch value {
    case .string(let string): return .string(redact(string))
    case .stringConvertible(let value): return .string(redact("\(value)"))
    case .dictionary(let dictionary): return .dictionary(redact(dictionary))
    case .array(let array): return .array(array.map { redact($0, forKey: key) })
    }
  }

  /// `scheme://host/path`, then the `?query` or `#fragment` that the match drops. It also reads
  /// the `https:\/\/` that `JSONSerialization` writes.
  nonisolated(unsafe) private static let urlWithQueryOrFragment =
    #/([A-Za-z][A-Za-z0-9+.\-]*:\\?/\\?/[^\s?#"'<>]*)[?#][^\s"'<>]*/#

  /// A sensitive key, its separator, and the start of its value; then the value up to the next
  /// delimiter. Covers `key=value`, `key: value`, `"key" : "value"`, `key: Optional("value")`, and
  /// the same inside a JSON string, where the quotes are escaped.
  ///
  /// The scan is not anchored, so `token` also matches the end of `refresh_token` and `id_token`.
  /// The alternation lists only the stems; ``sensitiveKeys`` holds the full names. The match is
  /// case-sensitive, and a capitalized stem counts only after a lowercase letter, as in
  /// `refreshToken`. That keeps a server message such as `Invalid Refresh Token: Already Used`
  /// readable.
  nonisolated(unsafe) private static let sensitivePair =
    #/((?:token_?[Hh]ash|auth_?[Cc]ode|api_?[Kk]ey|token|secret|otp|password|verifier|[a-z](?:Token|Secret|OTP|Otp|Password|Verifier))\\?"?\s*[:=]\s*(?:Optional\()?\\?"?)[^\s"',&)}\]\\]+/#

  nonisolated(unsafe) private static let jwt = #/eyJ[\w\-]+\.[\w\-]+\.[\w\-]*/#

  /// A secret API key, which does not have the shape of a JWT.
  nonisolated(unsafe) private static let secretAPIKey = #/sb_secret_[\w\-]+/#
}

/// A `LogHandler` that redacts each message and its metadata, then forwards it to `base`.
///
/// It forwards through `base.log(...)`, so the base logger keeps its handler, level, and
/// metadata.
package struct RedactingLogHandler: LogHandler {
  private(set) var base: Logging.Logger
  private var redactedMetadata: Logging.Logger.Metadata = [:]

  /// Redacted once, when set: the SDK sets it (`system`, `client_id`, `requestID`) and every line
  /// reads it.
  package var metadata: Logging.Logger.Metadata {
    get { redactedMetadata }
    set { redactedMetadata = LogRedaction.redact(newValue) }
  }

  package var logLevel: Logging.Logger.Level {
    get { base.logLevel }
    set { base.logLevel = newValue }
  }

  package init(wrapping base: Logging.Logger) {
    self.base = base
  }

  package subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
    get { redactedMetadata[key] }
    set { redactedMetadata[key] = newValue.map { LogRedaction.redact($0, forKey: key) } }
  }

  package func log(
    level: Logging.Logger.Level,
    message: Logging.Logger.Message,
    metadata callMetadata: Logging.Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    var merged = redactedMetadata
    if let callMetadata {
      merged.merge(LogRedaction.redact(callMetadata)) { _, new in new }
    }
    base.log(
      level: level,
      Logging.Logger.Message(stringLiteral: LogRedaction.redact(message.description)),
      metadata: merged,
      source: source,
      file: file,
      function: function,
      line: line
    )
  }
}

extension Logging.Logger {
  /// A logger that removes secrets from every message and metadata value, then logs through `self`.
  ///
  /// Returns `self` when it already redacts, so each client can call it at init.
  package func redactingSecrets() -> Logging.Logger {
    if handler is RedactingLogHandler { return self }
    return Logging.Logger(label: label) { [self] _ in RedactingLogHandler(wrapping: self) }
  }
}
