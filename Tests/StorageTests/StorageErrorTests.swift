import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Storage

@Suite
struct StorageErrorTests {
  private static func serverError(_ json: String) -> StorageError {
    StorageAPI.serverError(HTTPResponse(status: .badRequest), body: Data(json.utf8))
  }

  @Test
  func serverErrorDecodesTheWirePayload() {
    let error = Self.serverError(
      #"{"statusCode": "403", "message": "Unauthorized access", "error": "Forbidden"}"#)

    #expect(error.serverError?.statusCode == 403)
    #expect(error.serverError?.message == "Unauthorized access")
    #expect(error.serverError?.error == "Forbidden")
    #expect(error.code == nil)
  }

  @Test
  func serverErrorDecodesANumericStatusCode() {
    let error = Self.serverError(
      #"{"statusCode":404,"message":"Object not found","code":"NoSuchKey"}"#)

    #expect(error.serverError?.statusCode == 404)
    #expect(error.code == .noSuchKey)
  }

  @Test
  func serverErrorLeavesANonNumericStatusCodeNil() {
    let error = Self.serverError(#"{"statusCode":"teapot","message":"Error"}"#)

    #expect(error.serverError?.statusCode == nil)
  }

  @Test
  func serverErrorDecodesTheIcebergShape() {
    let error = Self.serverError(
      #"{"error":{"message":"Namespace does not exist","type":"NoSuchNamespaceException","code":404}}"#
    )

    #expect(error.message == "Namespace does not exist")
    #expect(error.serverError?.error == "NoSuchNamespaceException")
    #expect(error.code == "NoSuchNamespaceException")
    #expect(error.serverError?.statusCode == 404)
  }

  @Test
  func serverErrorDecodesAnIcebergStringCode() {
    let error = Self.serverError(
      #"{"error":{"message":"Missing","type":"NotFound","code":"NoSuchCatalog"}}"#)

    #expect(error.code == .noSuchCatalog)
    #expect(error.serverError?.statusCode == nil)
  }

  @Test
  func serverErrorKeepsACodeItDoesNotKnow() {
    let error = Self.serverError(#"{"message":"Error","code":"SomeFutureCode"}"#)

    #expect(error.code == "SomeFutureCode")
    #expect(error.code?.rawValue == "SomeFutureCode")
  }

  @Test
  func serverErrorDecodesWithOnlyAMessage() {
    let error = Self.serverError(#"{"message":"Error"}"#)

    #expect(error.serverError?.statusCode == nil)
    #expect(error.serverError?.error == nil)
    #expect(error.code == nil)
    #expect(error.message == "Error")
  }

  @Test
  func catchMatchesKindAndCode() {
    let error: any Error = StorageError(kind: .server, message: "missing", code: .noSuchKey)

    #expect(StorageError.Kind.server ~= error)
    #expect(!(StorageError.Kind.transport ~= error))
    #expect(StorageError.Code.noSuchKey ~= error)
    #expect(!(StorageError.Code.noSuchBucket ~= error))
    #expect(!(StorageError.Code.noSuchKey ~= URLError(.timedOut)))
    #expect(!(StorageError.Kind.server ~= URLError(.timedOut)))

    do {
      throw error
    } catch StorageError.Code.noSuchKey {
    } catch {
      Issue.record("Expected StorageError.Code.noSuchKey, got \(error)")
    }
  }

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
    (.invalidUploadID, "InvalidUploadId"),
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
    (.invalidAccessKeyID, "InvalidAccessKeyId"),
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
    #expect(error.serverError?.statusCode == 400)
  }

  @Test
  func serverErrorPromotesCodeAndStatusFromTheBody() {
    let body = Data(
      #"{"statusCode":"404","error":"not_found","message":"Object not found","code":"NoSuchKey"}"#
        .utf8)

    let error = StorageAPI.serverError(HTTPResponse(status: .badRequest), body: body)

    #expect(error.code == .noSuchKey)
    #expect(error.serverError?.statusCode == 404)
    #expect(error.response?.status == 400)
    #expect(error.isNotFound)
  }

  @Test
  func plainTextBodyBecomesTheMessageWithoutACode() {
    let error = StorageAPI.serverError(
      HTTPResponse(status: .conflict, headerFields: [.contentType: "text/plain; charset=utf-8"]),
      body: Data("The resource already exists\n".utf8))

    #expect(error.kind == .server)
    #expect(error.message == "The resource already exists")
    #expect(error.code == nil)
    #expect(error.serverError?.statusCode == 409)
    #expect(error.serverError?.message == "The resource already exists")
  }

  @Test
  func plainTextNotFoundIsNotFound() {
    let error = StorageAPI.serverError(
      HTTPResponse(status: .notFound, headerFields: [.contentType: "text/plain"]),
      body: Data("Upload not found".utf8))

    #expect(error.code == nil)
    #expect(error.isNotFound)
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
      configuration: StorageClient.Configuration(
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
        response: HTTPErrorResponse(status: 404, headers: [:], body: Data())
      ).isNotFound)
    #expect(
      StorageError(
        kind: .server, message: "", serverError: .init(statusCode: 404, message: "")
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
      response: HTTPErrorResponse(status: 404, headers: HTTPFields(), body: Data())
    )

    #expect(error.description == "StorageError(server): Object not found [status 404]")
  }

  @Test
  func conformsToSupabaseError() {
    let error: any Error = StorageError(kind: .transport, message: "offline")

    #expect((error as? any SupabaseError)?.message == "offline")
  }
}
