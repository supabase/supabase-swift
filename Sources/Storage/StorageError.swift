public import Foundation
import OpenAPIRuntime

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
public struct StorageError: Error, Decodable, Sendable {
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

extension StorageError: LocalizedError {
  /// A localized description of the error, equal to ``message``.
  public var errorDescription: String? {
    message
  }
}

extension StorageError {
  /// A generic placeholder used only when a response is neither a recognized success nor a
  /// decodable error shape (should not happen against a spec-conforming server).
  static func unexpectedResponse() -> StorageError {
    StorageError(statusCode: nil, message: "Unexpected response from Storage API")
  }

  /// Builds a ``StorageError`` from a documented `errorSchema`-shaped generated response body
  /// (the `.forbidden` case, which has no separate status code of its own).
  init(decoding errorSchema: Components.Schemas.errorSchema, statusCode: String? = nil) {
    self.init(
      statusCode: statusCode ?? errorSchema.statusCode,
      message: errorSchema.message,
      error: errorSchema.error
    )
  }

  /// Builds a ``StorageError`` from a documented `errorSchema`-shaped generated response body
  /// (the `.clientError` case, which carries its own numeric HTTP status code).
  init(statusCode: Int, decoding errorSchema: Components.Schemas.errorSchema) {
    self.init(
      statusCode: String(statusCode),
      message: errorSchema.message,
      error: errorSchema.error
    )
  }

  /// Builds a ``StorageError`` from an `.undocumented` generated response, decoding the raw body
  /// bytes as ``StorageError`` JSON when possible (mirrors the non-OpenAPI fallback in
  /// ``StorageApi``'s `executeRequest`), falling back to a generic placeholder otherwise.
  init(
    statusCode: Int,
    undocumented payload: UndocumentedPayload,
    decoder: JSONDecoder
  ) async {
    if let body = payload.body,
      let data = try? await Data(collecting: body, upTo: .max),
      let error = try? decoder.decode(StorageError.self, from: data)
    {
      self = error
    } else {
      self = StorageError(
        statusCode: String(statusCode), message: "Unexpected response from Storage API")
    }
  }
}
