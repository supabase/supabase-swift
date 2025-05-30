import XCTest

@testable import Storage

final class FileOptionsTests: XCTestCase {
  func testDefaultInitialization() {
    let options = FileOptions()

    XCTAssertEqual(options.cacheControl, "3600")
    XCTAssertNil(options.contentType)
    XCTAssertFalse(options.upsert)
    XCTAssertNil(options.metadata)
  }

  func testCustomInitialization() {
    let metadata: [String: AnyJSON] = ["key": .string("value")]
    let options = FileOptions(
      cacheControl: "7200",
      contentType: "image/jpeg",
      upsert: true,
      metadata: metadata
    )

    XCTAssertEqual(options.cacheControl, "7200")
    XCTAssertEqual(options.contentType, "image/jpeg")
    XCTAssertTrue(options.upsert)
    XCTAssertEqual(options.metadata?["key"], .string("value"))
  }
}
