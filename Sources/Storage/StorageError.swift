import Foundation

public struct StorageError: Error, Decodable, Sendable {
  public var statusCode: String?
  public var message: String
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

// MARK: - StorageErrorCode

/// A typed code identifying the specific error returned by the Storage server.
///
/// Known server error strings are exposed as static constants. Because the server may return
/// codes not listed here, the type is open-ended: any unrecognised string is representable
/// without breaking existing `switch` statements.
public struct StorageErrorCode: RawRepresentable, Sendable, Hashable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.init(rawValue: rawValue) }
}

extension StorageErrorCode {
  /// Fallback used when the server returns an unrecognised code or a non-JSON body.
  public static let unknown = StorageErrorCode("unknown")

  // Authentication / authorisation
  public static let invalidJWT = StorageErrorCode("InvalidJWT")
  public static let unauthorized = StorageErrorCode("Unauthorized")

  // Object / bucket
  /// The requested object does not exist.
  public static let objectNotFound = StorageErrorCode("not_found")
  /// The requested bucket does not exist.
  public static let bucketNotFound = StorageErrorCode("Bucket not found")
  /// An object at the given path already exists and upsert was not requested.
  public static let objectAlreadyExists = StorageErrorCode("Duplicate")
  /// A bucket with the given name already exists.
  /// Note: the server uses the same "Duplicate" wire value for both object and bucket conflicts.
  public static let bucketAlreadyExists = StorageErrorCode("Duplicate")
  public static let invalidBucketName = StorageErrorCode("Invalid Input")

  // Upload
  public static let entityTooLarge = StorageErrorCode("Payload too large")
  public static let invalidMimeType = StorageErrorCode("invalid_mime_type")
}

// MARK: - StorageError convenience

extension StorageError {
  /// A typed error code derived from the server's `error` field.
  /// Returns `.unknown` when `error` is `nil`.
  public var errorCode: StorageErrorCode {
    guard let error else { return .unknown }
    return StorageErrorCode(rawValue: error)
  }

  /// `true` when the error indicates the requested object or bucket does not exist (404).
  public var isNotFound: Bool {
    errorCode == .objectNotFound || errorCode == .bucketNotFound
  }

  /// `true` when the error indicates the caller is not authenticated or authorised (401/403).
  public var isUnauthorized: Bool {
    errorCode == .unauthorized || errorCode == .invalidJWT
  }

  /// `true` when the uploaded file exceeds the configured size limit (413).
  public var isEntityTooLarge: Bool {
    errorCode == .entityTooLarge
  }
}
