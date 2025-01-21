import XCTest

@testable import Storage

final class BucketOptionsTests: XCTestCase {
  func testDefaultInitialization() {
    let options = BucketOptions()

    XCTAssertFalse(options.public)
    XCTAssertNil(options.fileSizeLimit)
    XCTAssertNil(options.allowedMimeTypes)
  }

  func testCustomInitialization() {
    let options = BucketOptions(
      public: true,
      fileSizeLimit: "5242880",
      allowedMimeTypes: ["image/jpeg", "image/png"]
    )

    XCTAssertTrue(options.public)
    XCTAssertEqual(options.fileSizeLimit, "5242880")
    XCTAssertEqual(options.allowedMimeTypes, ["image/jpeg", "image/png"])
  }
}
