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
    XCTAssertEqual(options.fileSizeLimit, "5000000")
    XCTAssertEqual(options.allowedMimeTypes, ["image/jpeg", "image/png"])
  }

  func testIsPublicRename() {
    let options = BucketOptions(isPublic: true)
    XCTAssertTrue(options.isPublic)
  }

  func testFileSizeLimitInteger() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: StorageByteCount(5_000_000))
    XCTAssertEqual(options.fileSizeLimit, "5000000")
  }

  func testFileSizeLimitMegabytes() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: .megabytes(1.5))
    XCTAssertEqual(options.fileSizeLimit, "1.5mb")
  }

  func testFileSizeLimitIntegerLiteral() {
    let options = BucketOptions(fileSizeLimit: 5_000_000)
    XCTAssertEqual(options.fileSizeLimit, "5000000")
  }

  func testDeprecatedPublicBridge() {
    var options = BucketOptions(isPublic: false)
    options.public = true  // deprecated setter
    XCTAssertTrue(options.isPublic)
    XCTAssertTrue(options.public)  // deprecated getter
  }

  func testDeprecatedStringFileSizeLimitBridge() {
    let options = BucketOptions(public: false, fileSizeLimit: "5242880")
    XCTAssertEqual(options.fileSizeLimit, "5242880")
  }

  func testDeprecatedStringFileSizeLimitNil() {
    let options = BucketOptions(public: false, fileSizeLimit: nil)
    XCTAssertNil(options.fileSizeLimit)
  }

  func testStringLiteralHumanReadable() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: "1mb")
    XCTAssertEqual(options.fileSizeLimit, "1mb")
  }

  func testStringLiteralNumeric() {
    let options = BucketOptions(isPublic: false, fileSizeLimit: "5242880")
    XCTAssertEqual(options.fileSizeLimit, "5242880")
  }

  func testDeprecatedStringBridgeHumanReadable() {
    let options = BucketOptions(public: false, fileSizeLimit: "1mb")
    XCTAssertEqual(options.fileSizeLimit, "1mb")
  }
}
