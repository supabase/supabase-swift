import Foundation
import Storage
import Testing

@Suite
struct StorageErrorTests {
  @Test
  func initialization() {
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
    let json = Data(
      """
      {
        "statusCode": "403",
        "message": "Unauthorized access",
        "error": "Forbidden"
      }
      """.utf8
    )

    let error = try JSONDecoder().decode(StorageError.self, from: json)

    #expect(error.statusCode == "403")
    #expect(error.message == "Unauthorized access")
    #expect(error.error == "Forbidden")
  }
}
