import Foundation
import HTTPTypes
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

    #expect(payload.statusCode == "403")
    #expect(payload.message == "Unauthorized access")
    #expect(payload.error == "Forbidden")
  }

  @Test
  func serverErrorDecodesTheCode() throws {
    let json = Data(
      """
      {"statusCode":"404","error":"not_found","message":"Object not found","code":"NoSuchKey"}
      """.utf8)

    let payload = try JSONDecoder().decode(StorageError.ServerError.self, from: json)

    #expect(payload.code == .noSuchKey)
    #expect(payload.error == "not_found")
  }

  @Test
  func serverErrorKeepsACodeItDoesNotKnow() throws {
    let json = Data(#"{"message":"Error","code":"SomeFutureCode"}"#.utf8)

    let payload = try JSONDecoder().decode(StorageError.ServerError.self, from: json)

    #expect(payload.code == StorageError.Code("SomeFutureCode"))
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

  @Test
  func errorDescriptionIsTheMessage() {
    let error = StorageError(kind: .invalidURL, message: "Cannot build a public URL.")

    #expect(error.errorDescription == "Cannot build a public URL.")
  }

  @Test
  func descriptionIncludesKindAndStatus() {
    let error = StorageError(
      kind: .server,
      message: "Object not found",
      serverError: .init(statusCode: "404", error: "not_found", message: "Object not found"),
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
