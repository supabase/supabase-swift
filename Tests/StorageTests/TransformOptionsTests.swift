import XCTest

@testable import Storage

final class TransformOptionsTests: XCTestCase {
  func testDefaultInitialization() {
    let options = TransformOptions()

    XCTAssertNil(options.width)
    XCTAssertNil(options.height)
    XCTAssertNil(options.resize)
    XCTAssertNil(options.quality)
    XCTAssertNil(options.format)
  }

  func testIsEmpty_defaultOptions() {
    XCTAssertTrue(TransformOptions().isEmpty)
  }

  func testIsEmpty_withWidth() {
    XCTAssertFalse(TransformOptions(width: 200).isEmpty)
  }

  func testIsEmpty_withHeight() {
    XCTAssertFalse(TransformOptions(height: 300).isEmpty)
  }

  func testIsEmpty_withResize() {
    XCTAssertFalse(TransformOptions(resize: "cover").isEmpty)
  }

  func testIsEmpty_withQuality() {
    XCTAssertFalse(TransformOptions(quality: 90).isEmpty)
  }

  func testIsEmpty_withFormat() {
    XCTAssertFalse(TransformOptions(format: "webp").isEmpty)
  }

  func testCustomInitialization() {
    let options = TransformOptions(
      width: 100,
      height: 200,
      resize: "cover",
      quality: 90,
      format: "webp"
    )

    XCTAssertEqual(options.width, 100)
    XCTAssertEqual(options.height, 200)
    XCTAssertEqual(options.resize, "cover")
    XCTAssertEqual(options.quality, 90)
    XCTAssertEqual(options.format, "webp")
  }

  func testQueryItemsGeneration() {
    let options = TransformOptions(
      width: 100,
      height: 200,
      resize: "cover",
      quality: 90,
      format: "webp"
    )

    let queryItems = options.queryItems

    XCTAssertEqual(queryItems.count, 5)

    XCTAssertEqual(queryItems[0].name, "width")
    XCTAssertEqual(queryItems[0].value, "100")

    XCTAssertEqual(queryItems[1].name, "height")
    XCTAssertEqual(queryItems[1].value, "200")

    XCTAssertEqual(queryItems[2].name, "resize")
    XCTAssertEqual(queryItems[2].value, "cover")

    XCTAssertEqual(queryItems[3].name, "quality")
    XCTAssertEqual(queryItems[3].value, "90")

    XCTAssertEqual(queryItems[4].name, "format")
    XCTAssertEqual(queryItems[4].value, "webp")
  }

  func testPartialQueryItemsGeneration() {
    let options = TransformOptions(width: 100, quality: 75)

    let queryItems = options.queryItems

    XCTAssertEqual(queryItems.count, 2)

    XCTAssertEqual(queryItems[0].name, "width")
    XCTAssertEqual(queryItems[0].value, "100")

    XCTAssertEqual(queryItems[1].name, "quality")
    XCTAssertEqual(queryItems[1].value, "75")
  }
}
