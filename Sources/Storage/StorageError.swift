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

  /// A machine-readable code Storage sends alongside the error body.
  ///
  /// Compare against the static members and keep a fallback branch: Storage adds codes, and a
  /// server newer than the SDK can send one this version does not know.
  public struct Code: Decodable, RawRepresentable, Sendable, Hashable {
    public var rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
      self.init(rawValue: rawValue)
    }
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
    /// The machine-readable code, such as ``Code/noSuchKey``, when Storage sends one.
    public var code: Code?
    /// The human-readable message.
    public var message: String

    public init(
      statusCode: String? = nil, error: String? = nil, code: Code? = nil, message: String
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

// The codes Storage defines today. The server may send one that is not listed here, so treat
// unknown values as a normal outcome rather than a bug.
extension StorageError.Code {
  /// The specified bucket does not exist.
  public static let noSuchBucket = StorageError.Code("NoSuchBucket")

  /// The bucket has no lifecycle configuration.
  public static let noSuchLifecycleConfiguration = StorageError.Code("NoSuchLifecycleConfiguration")

  /// The specified key does not exist.
  public static let noSuchKey = StorageError.Code("NoSuchKey")

  /// The specified upload does not exist.
  public static let noSuchUpload = StorageError.Code("NoSuchUpload")

  /// The provided JWT is invalid.
  public static let invalidJWT = StorageError.Code("InvalidJWT")

  /// The request is not properly formed.
  public static let invalidRequest = StorageError.Code("InvalidRequest")

  /// An argument in the request is not valid.
  public static let invalidArgument = StorageError.Code("InvalidArgument")

  /// The request body is not well formed XML.
  public static let malformedXML = StorageError.Code("MalformedXML")

  /// The specified tenant does not exist.
  public static let tenantNotFound = StorageError.Code("TenantNotFound")

  /// The entity being uploaded is too large.
  public static let entityTooLarge = StorageError.Code("EntityTooLarge")

  /// An internal server error occurred.
  public static let internalError = StorageError.Code("InternalError")

  /// The specified resource already exists.
  public static let resourceAlreadyExists = StorageError.Code("ResourceAlreadyExists")

  /// The resource still has contents, such as a bucket that is not empty.
  public static let resourceNotEmpty = StorageError.Code("ResourceNotEmpty")

  /// The specified bucket name is invalid.
  public static let invalidBucketName = StorageError.Code("InvalidBucketName")

  /// The specified key is invalid.
  public static let invalidKey = StorageError.Code("InvalidKey")

  /// The specified range is not valid.
  public static let invalidRange = StorageError.Code("InvalidRange")

  /// The specified MIME type is not valid.
  public static let invalidMimeType = StorageError.Code("InvalidMimeType")

  /// The specified upload ID is invalid.
  public static let invalidUploadId = StorageError.Code("InvalidUploadId")

  /// The specified key already exists.
  public static let keyAlreadyExists = StorageError.Code("KeyAlreadyExists")

  /// The specified bucket already exists.
  public static let bucketAlreadyExists = StorageError.Code("BucketAlreadyExists")

  /// Timeout occurred while accessing the database.
  public static let databaseTimeout = StorageError.Code("DatabaseTimeout")

  /// The database is currently in read-only mode.
  public static let databaseReadOnly = StorageError.Code("DatabaseReadOnly")

  /// The database transaction was aborted and has to be rolled back before retrying.
  public static let databaseTransactionAborted = StorageError.Code("DatabaseTransactionAborted")

  /// The database schema is invalid or incompatible.
  public static let databaseInvalidObjectDefinition = StorageError.Code(
    "DatabaseInvalidObjectDefinition")

  /// The database schema is out of sync with Storage.
  public static let databaseSchemaMismatch = StorageError.Code("DatabaseSchemaMismatch")

  /// The signature provided does not match the calculated signature.
  public static let invalidSignature = StorageError.Code("InvalidSignature")

  /// The provided token has expired.
  public static let expiredToken = StorageError.Code("ExpiredToken")

  /// The request signature does not match the calculated signature.
  public static let signatureDoesNotMatch = StorageError.Code("SignatureDoesNotMatch")

  /// Access to the specified resource is denied.
  public static let accessDenied = StorageError.Code("AccessDenied")

  /// The specified resource is locked.
  public static let resourceLocked = StorageError.Code("ResourceLocked")

  /// The resource is still referenced by another resource.
  public static let resourceReferenced = StorageError.Code("ResourceReferenced")

  /// An error occurred while accessing the database.
  public static let databaseError = StorageError.Code("DatabaseError")

  /// The database transaction could not be completed.
  public static let transactionError = StorageError.Code("TransactionError")

  /// The Content-Length header is missing.
  public static let missingContentLength = StorageError.Code("MissingContentLength")

  /// A required parameter is missing in the request.
  public static let missingParameter = StorageError.Code("MissingParameter")

  /// A parameter in the request is not valid.
  public static let invalidParameter = StorageError.Code("InvalidParameter")

  /// The provided upload signature is invalid.
  public static let invalidUploadSignature = StorageError.Code("InvalidUploadSignature")

  /// Timeout occurred while waiting for a lock.
  public static let lockTimeout = StorageError.Code("LockTimeout")

  /// An error occurred in the S3 backend.
  public static let s3Error = StorageError.Code("S3Error")

  /// The provided access key ID is invalid.
  public static let invalidAccessKeyId = StorageError.Code("InvalidAccessKeyId")

  /// The maximum number of credentials has been reached.
  public static let maximumCredentialsLimit = StorageError.Code("MaximumCredentialsLimit")

  /// The checksum of the entity does not match.
  public static let invalidChecksum = StorageError.Code("InvalidChecksum")

  /// A part of the entity is missing.
  public static let missingPart = StorageError.Code("MissingPart")

  /// The request rate is too high and has been throttled.
  public static let slowDown = StorageError.Code("SlowDown")

  /// The resumable upload protocol reported an error.
  public static let tusError = StorageError.Code("TusError")

  /// The request was aborted.
  public static let aborted = StorageError.Code("Aborted")

  /// The request was aborted and the upload was terminated.
  public static let abortedTerminate = StorageError.Code("AbortedTerminate")

  /// The feature is not enabled for this resource.
  public static let featureNotEnabled = StorageError.Code("FeatureNotEnabled")

  /// The requested feature is not supported.
  public static let notSupported = StorageError.Code("NotSupported")

  /// The maximum number of this catalog resource has been reached.
  public static let icebergMaximumResourceLimit = StorageError.Code("IcebergMaximumResourceLimit")

  /// The catalog resource is not empty.
  public static let icebergResourceNotEmpty = StorageError.Code("IcebergResourceNotEmpty")

  /// The specified catalog does not exist.
  public static let noSuchCatalog = StorageError.Code("NoSuchCatalog")

  /// Storage could not classify the failure.
  public static let unknownError = StorageError.Code("UnknownError")

  /// The vector resource already exists.
  public static let conflictException = StorageError.Code("ConflictException")

  /// The vector resource does not exist.
  public static let notFoundException = StorageError.Code("NotFoundException")

  /// The vector bucket is not empty.
  public static let vectorBucketNotEmpty = StorageError.Code("VectorBucketNotEmpty")

  /// The maximum number of vector buckets has been reached.
  public static let s3VectorMaxBucketsExceeded = StorageError.Code("S3VectorMaxBucketsExceeded")

  /// The maximum number of vector indexes has been reached.
  public static let s3VectorMaxIndexesExceeded = StorageError.Code("S3VectorMaxIndexesExceeded")

  /// No shard is available to host the resource.
  public static let noAvailableShard = StorageError.Code("NoAvailableShard")

  /// The specified shard does not exist.
  public static let shardNotFound = StorageError.Code("ShardNotFound")
}
