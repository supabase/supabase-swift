import Foundation
public import Helpers

/// An error thrown by the Storage client.
///
/// Check ``kind`` to learn what failed. For ``Kind-swift.struct/server``, ``serverError`` holds
/// the body Storage returned and ``response`` holds the status, headers and request id.
///
/// ```swift
/// do {
///   try await storage.from("avatars").download(path: "missing.png")
/// } catch let error as StorageError where error.kind == .server {
///   print(error.response?.statusCode ?? 0, error.serverError?.error ?? "", error.message)
/// }
/// ```
public struct StorageError: SupabaseError {
  /// What failed. Compare against the static members and keep a fallback branch.
  public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// Storage rejected the request and sent a recognizable error body. See
    /// ``StorageError/serverError``.
    public static let server: Kind = "server"
    /// A non-2xx status whose body was not a Storage error payload. ``StorageError/response``
    /// has the raw body.
    public static let unexpectedResponse: Kind = "unexpectedResponse"
    /// The request never completed. ``StorageError/underlyingError`` is usually a `URLError`.
    public static let transport: Kind = "transport"
    /// A success body could not be decoded. ``StorageError/underlyingError`` is usually a
    /// `DecodingError`.
    public static let decoding: Kind = "decoding"
    /// A URL could not be built from the configuration and the given path. No request was sent.
    public static let invalidURL: Kind = "invalidURL"
  }

  /// The error body Storage returns for a rejected request, with its wire field names.
  public struct ServerError: Decodable, Hashable, Sendable {
    /// The HTTP status as Storage spells it in the body, e.g. `"404"`.
    ///
    /// Prefer ``HTTPErrorResponse/statusCode`` on the enclosing ``StorageError/response`` for
    /// the integer.
    public var statusCode: String?
    /// A short identifier such as `"not_found"` or `"Duplicate"`, when Storage sends one.
    public var error: String?
    /// A machine-readable code such as `"NoSuchKey"` or `"AccessDenied"`, when Storage sends one.
    ///
    /// See [Storage error codes](https://supabase.com/docs/guides/storage/debugging/error-codes).
    public var code: String?
    /// The human-readable message.
    public var message: String

    public init(
      statusCode: String? = nil, error: String? = nil, code: String? = nil, message: String
    ) {
      self.statusCode = statusCode
      self.error = error
      self.code = code
      self.message = message
    }
  }

  public var kind: Kind
  public var message: String
  /// The decoded error body. Non-nil exactly when ``kind`` is ``Kind-swift.struct/server``.
  public var serverError: ServerError?
  public var response: HTTPErrorResponse?
  public var underlyingError: (any Error)?

  public init(
    kind: Kind,
    message: String,
    serverError: ServerError? = nil,
    response: HTTPErrorResponse? = nil,
    underlyingError: (any Error)? = nil
  ) {
    self.kind = kind
    self.message = message
    self.serverError = serverError
    self.response = response
    self.underlyingError = underlyingError
  }

  public var description: String {
    formattedDescription(kind: kind.rawValue)
  }
}
