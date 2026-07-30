import Foundation
import Testing

@testable import Storage

@Suite
struct StorageErrorTests {
  @Test
  func errorInitialization() {
    let error = StorageError(
      statusCode: "404",
      message: "File not found",
      error: "NotFound"
    )

    #expect(error.statusCode == "404")
    #expect(error.message == "File not found")
    #expect(error.error == "NotFound")
  }

  @Test
  func localizedError() {
    let error = StorageError(
      statusCode: "500",
      message: "Internal server error",
      error: nil
    )

    #expect(error.errorDescription == "Internal server error")
  }

  @Test
  func decoding() throws {
    let json = """
      {
          "statusCode": "403",
          "message": "Unauthorized access",
          "error": "Forbidden"
      }
      """.data(using: .utf8)!

    let error = try JSONDecoder().decode(StorageError.self, from: json)

    #expect(error.statusCode == "403")
    #expect(error.message == "Unauthorized access")
    #expect(error.error == "Forbidden")
  }
}
