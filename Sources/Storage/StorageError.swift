public import Foundation

/// An error thrown by the Storage client.
///
/// ``StorageError`` is thrown when Storage answers with a non-2xx status and a Storage error
/// body. Check ``kind`` to learn what failed. For ``Kind-swift.struct/server``, ``code`` carries
/// the code Storage put in the body and ``serverError`` holds the rest of that body, including
/// the status Storage reports. On the object, bucket, render and CDN routes the HTTP status is
/// 400 for nearly every failure, so branch on ``code`` or `serverError?.statusCode`.
///
/// ```swift
/// do {
///   _ = try await storage.from("avatars").download(path: "missing.png")
/// } catch let error as StorageError where error.isNotFound {
///   showPlaceholder()
/// } catch let error as StorageError {
///   print(error.code?.rawValue ?? "", error.message)
/// }
/// ```
///
/// > Note: On this version a failure that is not a Storage error body is not a ``StorageError``.
/// > A non-2xx response with another body throws `HTTPError`, and `URLError` and `DecodingError`
/// > pass through unchanged.
public struct StorageError: Error, Decodable, Sendable {
  /// What failed. Compare against the static members and keep a fallback branch.
  public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    /// The kind's name, e.g. `"server"`.
    public let rawValue: String

    /// Creates a kind from its name.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Creates a kind from a string literal.
    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// Storage answered with a non-2xx status. Branch on ``StorageError/code`` and
    /// `serverError?.statusCode` for what Storage reported.
    public static let server: Kind = "server"
    /// No response arrived. On this version the client does not produce this kind: a transport
    /// failure is thrown as the underlying error, usually a `URLError`.
    public static let transport: Kind = "transport"
    /// Storage answered 2xx but the body could not be used because a required field was missing.
    /// On this version a body that does not decode as the expected type is thrown as a
    /// `DecodingError`.
    public static let decoding: Kind = "decoding"
    /// The SDK refused to send because a per-call value was not valid. Fix the call. No request
    /// was sent.
    public static let invalidRequest: Kind = "invalidRequest"
    /// The configuration was refused. On this version the client does not produce this kind.
    public static let invalidConfiguration: Kind = "invalidConfiguration"
    /// The access token provider threw. On this version the client does not produce this kind:
    /// the provider's error is thrown unchanged.
    public static let accessToken: Kind = "accessToken"
  }

  /// A machine-readable code Storage sends alongside the error body.
  ///
  /// Compare against the static members and keep a fallback branch: Storage adds codes, and a
  /// server newer than the SDK can send one this version does not know.
  public struct Code: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    /// The code as Storage sends it, e.g. `"NoSuchKey"`.
    public let rawValue: String

    /// Creates a code from the value Storage sends.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Creates a code from a string literal.
    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }
  }

  /// The error body Storage returns for a rejected request, without its code, which is
  /// ``StorageError/code``.
  ///
  /// Holds the flat shape Storage sends,
  /// `{"statusCode": "404", "error": "not_found", "message": "..."}`.
  public struct ServerError: Hashable, Sendable {
    /// The status Storage reports in the body, e.g. `404`, which is the real outcome when the
    /// HTTP status is 400.
    public var statusCode: Int?
    /// A short identifier such as `"not_found"` or `"Duplicate"`, when Storage sends one.
    public var error: String?
    /// The human-readable message.
    public var message: String

    /// Creates a ``ServerError``.
    public init(statusCode: Int? = nil, error: String? = nil, message: String) {
      self.statusCode = statusCode
      self.error = error
      self.message = message
    }
  }

  /// What failed. Check it first.
  public var kind: Kind
  /// A human-readable description of the failure, from Storage or from the SDK.
  public var message: String
  /// The code Storage sent, such as ``Code-swift.struct/noSuchKey``. Set when ``kind`` is
  /// ``Kind-swift.struct/server`` and the body carried one; `nil` otherwise.
  public var code: Code?
  /// The decoded error body. Set when ``kind`` is ``Kind-swift.struct/server``; `nil` otherwise.
  public var serverError: ServerError? {
    didSet { statusCodeText = serverError?.statusCode.map(String.init) }
  }

  /// The status exactly as Storage spelled it, which ``statusCode`` keeps returning.
  private var statusCodeText: String?

  /// The HTTP status code returned by the API, represented as a string (e.g. `"404"`).
  @available(*, deprecated, message: "Use serverError?.statusCode or isNotFound instead.")
  public var statusCode: String? {
    get { statusCodeText }
    set {
      var serverError = serverError ?? ServerError(message: message)
      serverError.statusCode = newValue.flatMap(Int.init)
      self.serverError = serverError
      statusCodeText = newValue
    }
  }

  /// A short error identifier string returned by the API, if available.
  @available(*, deprecated, message: "Use serverError?.error instead.")
  public var error: String? {
    get { serverError?.error }
    set {
      let statusCodeText = statusCodeText
      var serverError = serverError ?? ServerError(message: message)
      serverError.error = newValue
      self.serverError = serverError
      self.statusCodeText = statusCodeText
    }
  }

  /// Whether Storage reported that the object or bucket does not exist: ``code`` is
  /// ``Code-swift.struct/noSuchKey`` or ``Code-swift.struct/noSuchBucket``, or the status in the
  /// body is 404.
  public var isNotFound: Bool {
    code == .noSuchKey || code == .noSuchBucket || serverError?.statusCode == 404
  }

  /// Creates a ``StorageError``.
  ///
  /// - Parameters:
  ///   - kind: What failed.
  ///   - message: A human-readable description of the failure.
  ///   - code: The code Storage sent, if any.
  ///   - serverError: The decoded error body, if Storage sent one.
  public init(
    kind: Kind,
    message: String,
    code: Code? = nil,
    serverError: ServerError? = nil
  ) {
    self.kind = kind
    self.message = message
    self.code = code
    self.serverError = serverError
    self.statusCodeText = serverError?.statusCode.map(String.init)
  }

  /// Creates a ``StorageError`` of kind ``Kind-swift.struct/server``.
  ///
  /// - Parameters:
  ///   - statusCode: The HTTP status code string, if known.
  ///   - message: A human-readable description of the error.
  ///   - error: A short error identifier string, if available.
  @available(*, deprecated, message: "Use init(kind:message:code:serverError:) instead.")
  public init(statusCode: String? = nil, message: String, error: String? = nil) {
    self.init(serverStatusCode: statusCode, message: message, error: error, code: nil)
  }

  private init(serverStatusCode: String?, message: String, error: String?, code: Code?) {
    self.kind = .server
    self.message = message
    self.code = code
    self.serverError = ServerError(
      statusCode: serverStatusCode.flatMap(Int.init), error: error, message: message)
    self.statusCodeText = serverStatusCode
  }

  private enum CodingKeys: String, CodingKey {
    case statusCode, message, error, code
  }

  /// Decodes the error body Storage sends. The result has kind ``Kind-swift.struct/server``.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      serverStatusCode: try container.decodeIfPresent(String.self, forKey: .statusCode),
      message: try container.decode(String.self, forKey: .message),
      error: try container.decodeIfPresent(String.self, forKey: .error),
      code: (try? container.decodeIfPresent(String.self, forKey: .code)).flatMap { $0 }
        .map(Code.init(rawValue:))
    )
  }
}

extension StorageError: LocalizedError {
  /// A localized description of the error, equal to ``message``.
  public var errorDescription: String? {
    message
  }
}

extension StorageError.Code {
  /// The specified bucket does not exist.
  public static let noSuchBucket: StorageError.Code = "NoSuchBucket"

  /// The bucket has no lifecycle configuration.
  public static let noSuchLifecycleConfiguration: StorageError.Code = "NoSuchLifecycleConfiguration"

  /// The specified key does not exist.
  public static let noSuchKey: StorageError.Code = "NoSuchKey"

  /// The specified upload does not exist.
  public static let noSuchUpload: StorageError.Code = "NoSuchUpload"

  /// The provided JWT is invalid.
  public static let invalidJWT: StorageError.Code = "InvalidJWT"

  /// The request is not properly formed.
  public static let invalidRequest: StorageError.Code = "InvalidRequest"

  /// An argument in the request is not valid.
  public static let invalidArgument: StorageError.Code = "InvalidArgument"

  /// The request body is not well formed XML.
  public static let malformedXML: StorageError.Code = "MalformedXML"

  /// The specified tenant does not exist.
  public static let tenantNotFound: StorageError.Code = "TenantNotFound"

  /// The entity being uploaded is too large.
  public static let entityTooLarge: StorageError.Code = "EntityTooLarge"

  /// An internal server error occurred.
  public static let internalError: StorageError.Code = "InternalError"

  /// The specified resource already exists.
  public static let resourceAlreadyExists: StorageError.Code = "ResourceAlreadyExists"

  /// The resource still has contents, such as a bucket that is not empty.
  public static let resourceNotEmpty: StorageError.Code = "ResourceNotEmpty"

  /// The specified bucket name is invalid.
  public static let invalidBucketName: StorageError.Code = "InvalidBucketName"

  /// The specified key is invalid.
  public static let invalidKey: StorageError.Code = "InvalidKey"

  /// The specified range is not valid.
  public static let invalidRange: StorageError.Code = "InvalidRange"

  /// The specified MIME type is not valid.
  public static let invalidMimeType: StorageError.Code = "InvalidMimeType"

  /// The specified upload ID is invalid.
  public static let invalidUploadID: StorageError.Code = "InvalidUploadId"

  /// The specified key already exists.
  public static let keyAlreadyExists: StorageError.Code = "KeyAlreadyExists"

  /// The specified bucket already exists.
  public static let bucketAlreadyExists: StorageError.Code = "BucketAlreadyExists"

  /// Timeout occurred while accessing the database.
  public static let databaseTimeout: StorageError.Code = "DatabaseTimeout"

  /// The database is currently in read-only mode.
  public static let databaseReadOnly: StorageError.Code = "DatabaseReadOnly"

  /// The database transaction was aborted and has to be rolled back before retrying.
  public static let databaseTransactionAborted: StorageError.Code = "DatabaseTransactionAborted"

  /// The database schema is invalid or incompatible.
  public static let databaseInvalidObjectDefinition: StorageError.Code =
    "DatabaseInvalidObjectDefinition"

  /// The database schema is out of sync with Storage.
  public static let databaseSchemaMismatch: StorageError.Code = "DatabaseSchemaMismatch"

  /// The signature provided does not match the calculated signature.
  public static let invalidSignature: StorageError.Code = "InvalidSignature"

  /// The provided token has expired.
  public static let expiredToken: StorageError.Code = "ExpiredToken"

  /// The request signature does not match the calculated signature.
  public static let signatureDoesNotMatch: StorageError.Code = "SignatureDoesNotMatch"

  /// Access to the specified resource is denied.
  public static let accessDenied: StorageError.Code = "AccessDenied"

  /// The specified resource is locked.
  public static let resourceLocked: StorageError.Code = "ResourceLocked"

  /// The resource is still referenced by another resource.
  public static let resourceReferenced: StorageError.Code = "ResourceReferenced"

  /// An error occurred while accessing the database.
  public static let databaseError: StorageError.Code = "DatabaseError"

  /// The database transaction could not be completed.
  public static let transactionError: StorageError.Code = "TransactionError"

  /// The Content-Length header is missing.
  public static let missingContentLength: StorageError.Code = "MissingContentLength"

  /// A required parameter is missing in the request.
  public static let missingParameter: StorageError.Code = "MissingParameter"

  /// A parameter in the request is not valid.
  public static let invalidParameter: StorageError.Code = "InvalidParameter"

  /// The provided upload signature is invalid.
  public static let invalidUploadSignature: StorageError.Code = "InvalidUploadSignature"

  /// Timeout occurred while waiting for a lock.
  public static let lockTimeout: StorageError.Code = "LockTimeout"

  /// An error occurred in the S3 backend.
  public static let s3Error: StorageError.Code = "S3Error"

  /// The provided access key ID is invalid.
  public static let invalidAccessKeyID: StorageError.Code = "InvalidAccessKeyId"

  /// The maximum number of credentials has been reached.
  public static let maximumCredentialsLimit: StorageError.Code = "MaximumCredentialsLimit"

  /// The checksum of the entity does not match.
  public static let invalidChecksum: StorageError.Code = "InvalidChecksum"

  /// A part of the entity is missing.
  public static let missingPart: StorageError.Code = "MissingPart"

  /// The request rate is too high and has been throttled.
  public static let slowDown: StorageError.Code = "SlowDown"

  /// The resumable upload protocol reported an error.
  public static let tusError: StorageError.Code = "TusError"

  /// The request was aborted.
  public static let aborted: StorageError.Code = "Aborted"

  /// The request was aborted and the upload was terminated.
  public static let abortedTerminate: StorageError.Code = "AbortedTerminate"

  /// The feature is not enabled for this resource.
  public static let featureNotEnabled: StorageError.Code = "FeatureNotEnabled"

  /// The requested feature is not supported.
  public static let notSupported: StorageError.Code = "NotSupported"

  /// The maximum number of this catalog resource has been reached.
  public static let icebergMaximumResourceLimit: StorageError.Code = "IcebergMaximumResourceLimit"

  /// The catalog resource is not empty.
  public static let icebergResourceNotEmpty: StorageError.Code = "IcebergResourceNotEmpty"

  /// The specified catalog does not exist.
  public static let noSuchCatalog: StorageError.Code = "NoSuchCatalog"

  /// Storage could not classify the failure.
  public static let unknownError: StorageError.Code = "UnknownError"

  /// The vector resource already exists.
  public static let conflictException: StorageError.Code = "ConflictException"

  /// The vector resource does not exist.
  public static let notFoundException: StorageError.Code = "NotFoundException"

  /// The vector bucket is not empty.
  public static let vectorBucketNotEmpty: StorageError.Code = "VectorBucketNotEmpty"

  /// The maximum number of vector buckets has been reached.
  public static let s3VectorMaxBucketsExceeded: StorageError.Code = "S3VectorMaxBucketsExceeded"

  /// The maximum number of vector indexes has been reached.
  public static let s3VectorMaxIndexesExceeded: StorageError.Code = "S3VectorMaxIndexesExceeded"

  /// No shard is available to host the resource.
  public static let noAvailableShard: StorageError.Code = "NoAvailableShard"

  /// The specified shard does not exist.
  public static let shardNotFound: StorageError.Code = "ShardNotFound"
}

extension StorageError.Kind {
  /// Matches a ``StorageError`` of this ``StorageError/kind``, so a `catch` clause can name the
  /// kind directly.
  ///
  /// ```swift
  /// do {
  ///   _ = try await storage.from("avatars").download(path: "a.png")
  /// } catch StorageError.Kind.server {
  ///   showServerError()
  /// }
  /// ```
  public static func ~= (kind: StorageError.Kind, error: any Error) -> Bool {
    (error as? StorageError)?.kind == kind
  }
}

extension StorageError.Code {
  /// Matches a ``StorageError`` with this ``StorageError/code``, so a `catch` clause can name the
  /// code directly.
  ///
  /// ```swift
  /// do {
  ///   _ = try await storage.from("avatars").download(path: "a.png")
  /// } catch StorageError.Code.noSuchKey {
  ///   showPlaceholder()
  /// }
  /// ```
  public static func ~= (code: StorageError.Code, error: any Error) -> Bool {
    (error as? StorageError)?.code == code
  }
}
