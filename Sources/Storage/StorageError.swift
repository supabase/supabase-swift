import Foundation

/// An error returned by the Supabase Storage API.
///
/// Storage operations throw `StorageError` when the server responds with a structured error
/// payload. Check ``message`` for a human-readable description of the failure and ``statusCode``
/// for the HTTP status code string when available.
///
/// ## Example
///
/// ```swift
/// do {
///   try await storage.from("avatars").upload("image.png", data: data)
/// } catch let error as StorageError {
///   print("Storage error \(error.statusCode ?? "?"): \(error.message)")
/// }
/// ```
public struct StorageError: Error, Decodable, Sendable {
  /// The HTTP status code returned by the server, represented as a string (e.g. `"404"`).
  ///
  /// May be `nil` when the error originates on the client side before a response is received.
  public var statusCode: String?

  /// A human-readable description of what went wrong.
  ///
  /// This value is also returned by ``LocalizedError/errorDescription``.
  public var message: String

  /// A short error code or category string provided by the server (e.g. `"not_found"`).
  ///
  /// May be `nil` when the server does not include an error code in the response.
  public var error: String?

  public init(statusCode: String? = nil, message: String, error: String? = nil) {
    self.statusCode = statusCode
    self.message = message
    self.error = error
  }
}

extension StorageError: LocalizedError {
  public var errorDescription: String? {
    message
  }
}
