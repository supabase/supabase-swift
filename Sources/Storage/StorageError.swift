//
//  StorageError.swift
//  Storage
//
//  Created by Guilherme Souza on 22/05/24.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A typed code identifying the specific error returned by the Storage server.
///
/// Known server error strings are exposed as static constants. Because the server may return codes
/// not listed here (e.g. when the SDK is older than the server), the type is open-ended: any
/// unrecognised string is representable without breaking existing `switch` statements.
///
/// ## Example
///
/// ```swift
/// catch let error as StorageError {
///   if error.errorCode == .objectNotFound { /* handle missing object */ }
/// }
/// ```
// Intentionally not Decodable — server JSON decoding is handled by the private
// ServerErrorResponse struct in StorageClient, which constructs StorageErrorCode values directly.
public struct StorageErrorCode: RawRepresentable, Sendable, Hashable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(_ rawValue: String) {
    self.init(rawValue: rawValue)
  }
}

extension StorageErrorCode {
  /// Fallback used when the server returns an unrecognised code or a non-JSON body.
  public static let unknown = StorageErrorCode("unknown")

  // MARK: - Authentication / authorisation

  /// No API key was supplied with the request.
  public static let noApiKey = StorageErrorCode("NoApiKeyFound")
  /// The JWT supplied with the request is invalid.
  public static let invalidJWT = StorageErrorCode("InvalidJWT")
  /// The request was rejected because the caller is not authorised.
  public static let unauthorized = StorageErrorCode("Unauthorized")

  // MARK: - Object / bucket

  /// Generic not-found response (no further specificity from the server).
  public static let notFound = StorageErrorCode("NotFound")
  /// The requested object does not exist.
  public static let objectNotFound = StorageErrorCode("ObjectNotFound")
  /// The requested bucket does not exist.
  public static let bucketNotFound = StorageErrorCode("BucketNotFound")
  /// An object at the given path already exists and upsert was not requested.
  public static let objectAlreadyExists = StorageErrorCode("Duplicate")
  /// A bucket with the given name already exists.
  public static let bucketAlreadyExists = StorageErrorCode("BucketAlreadyExists")
  /// The bucket name does not meet naming requirements.
  public static let invalidBucketName = StorageErrorCode("InvalidBucketName")

  // MARK: - Upload

  /// The uploaded file exceeds the configured size limit.
  public static let entityTooLarge = StorageErrorCode("EntityTooLarge")
  /// The MIME type of the uploaded file is not allowed.
  public static let invalidMimeType = StorageErrorCode("InvalidMimeType")
  /// The request did not include a Content-Type header.
  public static let missingContentType = StorageErrorCode("MissingContentType")

  // MARK: - Client-side synthetic codes (no HTTP response)

  /// The signed upload URL returned by the server contained no upload token.
  public static let noTokenReturned = StorageErrorCode("noTokenReturned")
}

/// An error thrown by the Supabase Storage API.
///
/// All Storage operations throw ``StorageError`` on failure. Use ``message`` for a human-readable
/// description, ``errorCode`` to identify the specific failure kind, and ``statusCode`` for the
/// HTTP status when the error originated from a server response.
///
/// Adding new ``StorageErrorCode`` constants in future SDK versions is not a breaking change.
///
/// ## Example
///
/// ```swift
/// do {
///   try await storage.from("avatars").upload("image.png", data: data)
/// } catch let error as StorageError {
///   switch error.errorCode {
///   case .objectAlreadyExists:
///     print("File already exists — use upsert: true to overwrite")
///   case .entityTooLarge:
///     print("File is too large")
///   default:
///     print("Storage error \(error.statusCode ?? -1): \(error.message)")
///   }
/// }
/// ```
public struct StorageError: Error, Sendable {
  /// A human-readable description of what went wrong.
  public let message: String

  /// A typed error code identifying the specific failure.
  ///
  /// Set to ``StorageErrorCode/unknown`` when the server returns an unrecognised code or a
  /// non-JSON response body.
  public let errorCode: StorageErrorCode

  /// The HTTP status code returned by the server.
  ///
  /// `nil` for client-side errors that have no associated HTTP response
  /// (e.g. ``StorageError/noTokenReturned``).
  public let statusCode: Int?

  /// The raw HTTP response, available for advanced debugging.
  ///
  /// `nil` for client-side errors.
  public let underlyingResponse: HTTPURLResponse?

  /// The raw response body, available for advanced debugging.
  ///
  /// `nil` for client-side errors.
  public let underlyingData: Data?

  /// Creates a ``StorageError``.
  public init(
    message: String,
    errorCode: StorageErrorCode,
    statusCode: Int? = nil,
    underlyingResponse: HTTPURLResponse? = nil,
    underlyingData: Data? = nil
  ) {
    self.message = message
    self.errorCode = errorCode
    self.statusCode = statusCode
    self.underlyingResponse = underlyingResponse
    self.underlyingData = underlyingData
  }
}

extension StorageError {
  /// `true` when the error indicates that the requested object or bucket does not exist.
  ///
  /// Covers HTTP status code 404 and the explicit error codes
  /// ``StorageErrorCode/objectNotFound``, ``StorageErrorCode/bucketNotFound``, and
  /// ``StorageErrorCode/notFound``.
  public var isNotFound: Bool {
    statusCode == 404
      || errorCode == .objectNotFound
      || errorCode == .bucketNotFound
      || errorCode == .notFound
  }

  /// `true` when the error indicates an authentication or authorisation failure (status 401 or 403).
  public var isUnauthorized: Bool {
    statusCode == 401 || statusCode == 403
  }
}

extension StorageError {
  /// Thrown when the signed upload URL returned by the server contains no upload token.
  public static let noTokenReturned = StorageError(
    message: "No token returned by API",
    errorCode: .noTokenReturned
  )
}

extension StorageError: LocalizedError {
  public var errorDescription: String? {
    message
  }
}

extension StorageErrorCode {
  // MARK: - Transfer errors (client-side)

  /// A network error occurred during a transfer (transient; retriable on resume).
  public static let networkError = StorageErrorCode("NetworkError")
  /// A file system operation (move or read) failed during a transfer.
  public static let fileSystemError = StorageErrorCode("FileSystemError")
  /// The transfer was explicitly cancelled or the enclosing Swift Task was cancelled.
  public static let cancelled = StorageErrorCode("Cancelled")
}

extension StorageError {
  static func networkError(underlying: any Error) -> StorageError {
    StorageError(message: underlying.localizedDescription, errorCode: .networkError)
  }

  static func fileSystemError(underlying: any Error) -> StorageError {
    StorageError(message: underlying.localizedDescription, errorCode: .fileSystemError)
  }

  static let cancelled = StorageError(
    message: "Transfer was cancelled",
    errorCode: .cancelled
  )
}
