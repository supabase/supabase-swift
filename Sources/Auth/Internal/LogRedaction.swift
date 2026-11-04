import Logging

/// Removes secrets from a log line before swift-log passes it to a handler.
///
/// `OSLogHandler` prints the rendered text as `.public`, so a secret has to be gone before the
/// handler sees it. The rules are a backstop: the typed descriptions of `Session`, `AuthChange`,
/// and `PendingFlowRecord` keep tokens out of an interpolated value in the first place.
enum LogRedaction {
  static let placeholder = "<redacted>"

  /// The keys whose values never appear in a log, in lowercase without separators. Matched as
  /// `refresh_token`, `refreshToken`, and `refreshtoken` alike.
  static let sensitiveKeys: Set<String> = [
    "accesstoken", "refreshtoken", "idtoken", "providertoken", "providerrefreshtoken",
    "codeverifier", "authcode", "verifier", "tokenhash", "hashedtoken", "emailotp", "otp",
    "password",
    "clientsecret", "secret", "token",
  ]

  static func redact(_ text: String) -> String {
    var result = text
    if result.contains("://") || result.contains(#":\/"#) {
      result.replace(urlWithQueryOrFragment) { String($0.output.1) }
    }
    result.replace(sensitivePair) { "\($0.output.1)\(placeholder)" }
    if result.contains("eyJ") {
      result.replace(jwt) { _ in placeholder }
    }
    return result
  }

  static func isSensitive(key: String) -> Bool {
    sensitiveKeys.contains(key.lowercased().filter { $0 != "_" && $0 != "-" })
  }

  static func redact(_ metadata: Logging.Logger.Metadata) -> Logging.Logger.Metadata {
    metadata.reduce(into: [:]) { $0[$1.key] = redact($1.value, forKey: $1.key) }
  }

  static func redact(
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
    #/((?:token_?[Hh]ash|auth_?[Cc]ode|token|secret|otp|password|verifier|[a-z](?:Token|Secret|OTP|Otp|Password|Verifier))\\?"?\s*[:=]\s*(?:Optional\()?\\?"?)[^\s"',&)}\]\\]+/#

  nonisolated(unsafe) private static let jwt = #/eyJ[\w\-]+\.[\w\-]+\.[\w\-]*/#
}

/// A `LogHandler` that redacts each message and its metadata, then forwards it to `base`.
///
/// It forwards through `base.log(...)`, so the base logger keeps its handler, level, and
/// metadata.
struct RedactingLogHandler: LogHandler {
  private var base: Logging.Logger
  private var redactedMetadata: Logging.Logger.Metadata = [:]

  /// Redacted once, when set: the SDK sets it (`system`, `client_id`, `requestID`) and every line
  /// reads it.
  var metadata: Logging.Logger.Metadata {
    get { redactedMetadata }
    set { redactedMetadata = LogRedaction.redact(newValue) }
  }

  var logLevel: Logging.Logger.Level {
    get { base.logLevel }
    set { base.logLevel = newValue }
  }

  init(wrapping base: Logging.Logger) {
    self.base = base
  }

  subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
    get { redactedMetadata[key] }
    set { redactedMetadata[key] = newValue.map { LogRedaction.redact($0, forKey: key) } }
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
  func redactingSecrets() -> Logging.Logger {
    Logging.Logger(label: label) { [self] _ in RedactingLogHandler(wrapping: self) }
  }
}
