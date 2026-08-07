public import Foundation

/// An error returned by the Supabase Storage API.
///
/// ``StorageError`` is thrown whenever the server responds with a non-2xx status code or when the
/// response body contains a recognizable error payload. Inspect ``message`` for a human-readable
/// description, and ``statusCode`` for the HTTP status code string returned by the API.
///
/// ```swift
/// do {
///   try await storage.from("avatars").download(path: "missing.png")
/// } catch let error as StorageError {
///   print(error.statusCode ?? "unknown", error.message)
/// }
/// ```
public struct StorageError: Error, Sendable {
  /// The HTTP status code returned by the API, represented as a string (e.g. `"404"`).
  public var statusCode: String?

  /// A human-readable description of the error.
  public var message: String

  /// A short error identifier string returned by the API, if available.
  public var error: String?

  /// Creates a ``StorageError``.
  ///
  /// - Parameters:
  ///   - statusCode: The HTTP status code string, if known.
  ///   - message: A human-readable description of the error.
  ///   - error: A short error identifier string, if available.
  public init(statusCode: String? = nil, message: String, error: String? = nil) {
    self.statusCode = statusCode
    self.message = message
    self.error = error
  }
}

extension StorageError: Decodable {
  /// The flat `{ statusCode, message, error }` shape used by most Storage endpoints.
  private struct FlatBody: Decodable {
    var statusCode: String?
    var message: String
    var error: String?
  }

  /// The `{ error: { message, type, code } }` shape used by the analytics/Iceberg endpoints,
  /// which run through a different error formatter on the backend.
  private struct NestedBody: Decodable {
    struct Inner: Decodable {
      var message: String
      var type: String?
      var code: Int?
    }

    var error: Inner
  }

  public init(from decoder: any Decoder) throws {
    if let flat = try? FlatBody(from: decoder) {
      self.init(statusCode: flat.statusCode, message: flat.message, error: flat.error)
      return
    }

    let nested = try NestedBody(from: decoder)
    self.init(
      statusCode: nested.error.code.map(String.init),
      message: nested.error.message,
      error: nested.error.type
    )
  }
}

extension StorageError: LocalizedError {
  /// A localized description of the error, equal to ``message``.
  public var errorDescription: String? {
    message
  }
}
