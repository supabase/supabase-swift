import XCTest

@testable import Storage

final class BucketOptionsTests: XCTestCase {
  func testDefaultInitialization() {
    let options = BucketOptions(isPublic: false)

    XCTAssertFalse(options.public)
    XCTAssertNil(options.fileSizeLimit)
    XCTAssertNil(options.allowedMimeTypes)
  }

  func testCustomInitialization() {
    let options = BucketOptions(
      public: true,
      fileSizeLimit: "5000000",
      allowedMimeTypes: ["image/jpeg", "image/png"]
    )

    XCTAssertTrue(options.public)
    XCTAssertEqual(options.fileSizeLimit?.intValue, 5_000_000)
    XCTAssertEqual(options.allowedMimeTypes, ["image/jpeg", "image/png"])
  }

  func testIsPublicRename() {
    let options = BucketOptions(isPublic: true)
    XCTAssertTrue(options.isPublic)
  }

  func testFileSizeLimitInteger() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: StorageByteCount(5_000_000))
    XCTAssertEqual(options.fileSizeLimit?.intValue, 5_000_000)
  }

  func testFileSizeLimitMegabytes() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: .megabytes(1.5))
    XCTAssertNil(options.fileSizeLimit?.intValue)
    XCTAssertEqual(options.fileSizeLimit?.stringValue, "1.5mb")
  }

  func testFileSizeLimitIntegerLiteral() {
    let options = BucketOptions(fileSizeLimit: 5_000_000)
    XCTAssertEqual(options.fileSizeLimit?.intValue, 5_000_000)
  }

  func testDeprecatedPublicBridge() {
    var options = BucketOptions(isPublic: false)
    options.public = true  // deprecated setter
    XCTAssertTrue(options.isPublic)
    XCTAssertTrue(options.public)  // deprecated getter
  }

  func testDeprecatedStringFileSizeLimitBridge() {
    let options = BucketOptions(public: false, fileSizeLimit: "5242880")
    XCTAssertEqual(options.fileSizeLimit?.intValue, 5_242_880)
  }

  func testDeprecatedStringFileSizeLimitNil() {
    let options = BucketOptions(public: false, fileSizeLimit: nil)
    XCTAssertNil(options.fileSizeLimit)
  }

  func testStringLiteralHumanReadable() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: "1mb")
    XCTAssertNil(options.fileSizeLimit?.intValue)
  }

  func testStringLiteralNumeric() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: "5242880")
    XCTAssertEqual(options.fileSizeLimit?.intValue, 5_242_880)
  }

  func testDeprecatedStringBridgeHumanReadable() {
    let options = BucketOptions(public: false, fileSizeLimit: "1mb")
    XCTAssertNil(options.fileSizeLimit?.intValue)
  }
}
