import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Storage

@Suite
struct StorageErrorTests {
  @Test
  func serverErrorDecodesTheWirePayload() throws {
    let json = Data(
      """
      {"statusCode": "403", "message": "Unauthorized access", "error": "Forbidden"}
      """.utf8)

    let payload = try JSONDecoder().decode(StorageError.ServerError.self, from: json)

    #expect(payload.statusCode == 403)
    #expect(payload.message == "Unauthorized access")
    #expect(payload.error == "Forbidden")
  }

  @Test
  func serverErrorDecodesANumericStatusCode() throws {
    let json = Data(#"{"statusCode":404,"message":"Object not found","code":"NoSuchKey"}"#.utf8)

    let payload = try JSONDecoder().decode(StorageError.ServerError.self, from: json)

    #expect(payload.statusCode == 404)
    #expect(payload.code == .noSuchKey)
  }

  @Test
  func serverErrorLeavesANonNumericStatusCodeNil() throws {
    let json = Data(#"{"statusCode":"teapot","message":"Error"}"#.utf8)

    let payload = try JSONDecoder().decode(StorageError.ServerError.self, from: json)

    #expect(payload.statusCode == nil)
  }

  @Test
  func serverErrorDecodesTheIcebergShape() throws {
    let json = Data(
      #"{"error":{"message":"Namespace does not exist","type":"NoSuchNamespaceException","code":404}}"#
        .utf8)

    let payload = try JSONDecoder().decode(StorageError.ServerError.self, from: json)

    #expect(payload.message == "Namespace does not exist")
    #expect(payload.error == "NoSuchNamespaceException")
    #expect(payload.code == "NoSuchNamespaceException")
    #expect(payload.statusCode == 404)
  }

  @Test
  func serverErrorKeepsACodeItDoesNotKnow() throws {
    let json = Data(#"{"message":"Error","code":"SomeFutureCode"}"#.utf8)

    let payload = try JSONDecoder().decode(StorageError.ServerError.self, from: json)

    #expect(payload.code == "SomeFutureCode")
    #expect(payload.code?.rawValue == "SomeFutureCode")
  }

  @Test
  func serverErrorDecodesWithOnlyAMessage() throws {
    let payload = try JSONDecoder().decode(
      StorageError.ServerError.self, from: Data(#"{"message":"Error"}"#.utf8))

    #expect(payload.statusCode == nil)
    #expect(payload.error == nil)
    #expect(payload.code == nil)
    #expect(payload.message == "Error")
  }

  /// Every code the SDK names, with the body Storage sends for it. A code the server adds later
  /// still decodes, as `Code(rawValue:)`; this pins that the named ones match their wire spelling.
  static let knownCodes: [(StorageError.Code, String)] = [
    (.noSuchBucket, "NoSuchBucket"),
    (.noSuchLifecycleConfiguration, "NoSuchLifecycleConfiguration"),
    (.noSuchKey, "NoSuchKey"),
    (.noSuchUpload, "NoSuchUpload"),
    (.invalidJWT, "InvalidJWT"),
    (.invalidRequest, "InvalidRequest"),
    (.invalidArgument, "InvalidArgument"),
    (.malformedXML, "MalformedXML"),
    (.tenantNotFound, "TenantNotFound"),
    (.entityTooLarge, "EntityTooLarge"),
    (.internalError, "InternalError"),
    (.resourceAlreadyExists, "ResourceAlreadyExists"),
    (.resourceNotEmpty, "ResourceNotEmpty"),
    (.invalidBucketName, "InvalidBucketName"),
    (.invalidKey, "InvalidKey"),
    (.invalidRange, "InvalidRange"),
    (.invalidMimeType, "InvalidMimeType"),
    (.invalidUploadId, "InvalidUploadId"),
    (.keyAlreadyExists, "KeyAlreadyExists"),
    (.bucketAlreadyExists, "BucketAlreadyExists"),
    (.databaseTimeout, "DatabaseTimeout"),
    (.databaseReadOnly, "DatabaseReadOnly"),
    (.databaseTransactionAborted, "DatabaseTransactionAborted"),
    (.databaseInvalidObjectDefinition, "DatabaseInvalidObjectDefinition"),
    (.databaseSchemaMismatch, "DatabaseSchemaMismatch"),
    (.invalidSignature, "InvalidSignature"),
    (.expiredToken, "ExpiredToken"),
    (.signatureDoesNotMatch, "SignatureDoesNotMatch"),
    (.accessDenied, "AccessDenied"),
    (.resourceLocked, "ResourceLocked"),
    (.resourceReferenced, "ResourceReferenced"),
    (.databaseError, "DatabaseError"),
    (.transactionError, "TransactionError"),
    (.missingContentLength, "MissingContentLength"),
    (.missingParameter, "MissingParameter"),
    (.invalidParameter, "InvalidParameter"),
    (.invalidUploadSignature, "InvalidUploadSignature"),
    (.lockTimeout, "LockTimeout"),
    (.s3Error, "S3Error"),
    (.invalidAccessKeyId, "InvalidAccessKeyId"),
    (.maximumCredentialsLimit, "MaximumCredentialsLimit"),
    (.invalidChecksum, "InvalidChecksum"),
    (.missingPart, "MissingPart"),
    (.slowDown, "SlowDown"),
    (.tusError, "TusError"),
    (.aborted, "Aborted"),
    (.abortedTerminate, "AbortedTerminate"),
    (.featureNotEnabled, "FeatureNotEnabled"),
    (.notSupported, "NotSupported"),
    (.icebergMaximumResourceLimit, "IcebergMaximumResourceLimit"),
    (.icebergResourceNotEmpty, "IcebergResourceNotEmpty"),
    (.noSuchCatalog, "NoSuchCatalog"),
    (.unknownError, "UnknownError"),
    (.conflictException, "ConflictException"),
    (.notFoundException, "NotFoundException"),
    (.vectorBucketNotEmpty, "VectorBucketNotEmpty"),
    (.s3VectorMaxBucketsExceeded, "S3VectorMaxBucketsExceeded"),
    (.s3VectorMaxIndexesExceeded, "S3VectorMaxIndexesExceeded"),
    (.noAvailableShard, "NoAvailableShard"),
    (.shardNotFound, "ShardNotFound"),
  ]

  @Test(arguments: knownCodes)
  func everyKnownCodeDecodesFromItsBody(code: StorageError.Code, raw: String) throws {
    let body = Data(
      #"{"statusCode":"400","error":"\#(raw)","message":"recorded","code":"\#(raw)"}"#.utf8)

    let error = StorageAPI.serverError(HTTPResponse(status: .badRequest), body: body)

    #expect(error.kind == .server)
    #expect(error.code == code)
    #expect(error.serverStatusCode == 400)
    #expect(error.serverError?.code == code)
  }

  @Test
  func serverErrorPromotesCodeAndStatusFromTheBody() {
    let body = Data(
      #"{"statusCode":"404","error":"not_found","message":"Object not found","code":"NoSuchKey"}"#
        .utf8)

    let error = StorageAPI.serverError(HTTPResponse(status: .badRequest), body: body)

    #expect(error.code == .noSuchKey)
    #expect(error.serverStatusCode == 404)
    #expect(error.response?.statusCode == 400)
    #expect(error.isNotFound)
  }

  @Test
  func plainTextBodyBecomesTheMessageWithTheCodeImpliedByTheStatus() {
    let error = StorageAPI.serverError(
      HTTPResponse(status: .conflict, headerFields: [.contentType: "text/plain; charset=utf-8"]),
      body: Data("The resource already exists\n".utf8))

    #expect(error.kind == .server)
    #expect(error.message == "The resource already exists")
    #expect(error.code == .keyAlreadyExists)
    #expect(error.serverStatusCode == 409)
    #expect(error.serverError?.message == "The resource already exists")
  }

  @Test(arguments: [(404, StorageError.Code.noSuchUpload), (413, .entityTooLarge), (500, nil)])
  func plainTextStatusMapsToACode(status: Int, code: StorageError.Code?) {
    let error = StorageAPI.serverError(
      HTTPResponse(status: .init(code: status), headerFields: [.contentType: "text/plain"]),
      body: Data("tus".utf8))

    #expect(error.code == code)
    #expect(error.serverStatusCode == status)
  }

  @Test
  func nonJSONNonTextBodyKeepsTheStatusMessage() {
    let error = StorageAPI.serverError(
      HTTPResponse(status: .badGateway, headerFields: [.contentType: "text/html"]),
      body: Data("<html>".utf8))

    #expect(error.message == "Unexpected response with status code 502.")
    #expect(error.code == nil)
    #expect(error.serverError == nil)
    #expect(error.response?.body == Data("<html>".utf8))
  }

  @Test
  func errorBodyIsCappedAtOneMebibyte() async throws {
    let oversized = Data(repeating: 0x78, count: StorageAPI.errorBodyCap + 4096)
    let storage = StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "http://localhost:54321/storage/v1")!,
        headers: [:],
        http: .init(
          transport: ClosureTransport { _, _ in
            (HTTPResponse(status: .badGateway), HTTPBody(oversized))
          }),
        retryEnabled: false
      ))

    await #expect {
      try await storage.listBuckets()
    } throws: { error in
      guard let error = error as? StorageError, let body = error.response?.body else {
        return false
      }
      return body.count == StorageAPI.errorBodyCap
    }
  }

  @Test
  func isNotFoundCoversBucketAndHTTPStatus() {
    #expect(StorageError(kind: .server, message: "", code: .noSuchBucket).isNotFound)
    #expect(
      StorageError(
        kind: .server, message: "",
        response: HTTPErrorResponse(statusCode: 404, headers: [:], body: Data())
      ).isNotFound)
    #expect(!StorageError(kind: .server, message: "", code: .invalidJWT).isNotFound)
    #expect(!StorageError(kind: .transport, message: "").isNotFound)
  }

  @Test
  func errorDescriptionIsTheMessage() {
    let error = StorageError(kind: .invalidRequest, message: "Cannot build a public URL.")

    #expect(error.errorDescription == "Cannot build a public URL.")
  }

  @Test
  func descriptionIncludesKindAndStatus() {
    let error = StorageError(
      kind: .server,
      message: "Object not found",
      serverError: .init(statusCode: 404, error: "not_found", message: "Object not found"),
      response: HTTPErrorResponse(statusCode: 404, headers: HTTPFields(), body: Data())
    )

    #expect(error.description == "StorageError(server): Object not found [status 404]")
  }

  @Test
  func conformsToSupabaseError() {
    let error: any Error = StorageError(kind: .transport, message: "offline")

    #expect((error as? any SupabaseError)?.message == "offline")
  }
}
