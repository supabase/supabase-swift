import XCTest

@testable import Storage

final class ValueTypesTests: XCTestCase {

  // MARK: - ResizeMode

  func testResizeMode_knownValues() {
    XCTAssertEqual(ResizeMode.cover.rawValue, "cover")
    XCTAssertEqual(ResizeMode.contain.rawValue, "contain")
    XCTAssertEqual(ResizeMode.fill.rawValue, "fill")
  }

  func testResizeMode_customValue() {
    let custom = ResizeMode(rawValue: "fit")
    XCTAssertEqual(custom.rawValue, "fit")
  }

  func testResizeMode_stringLiteral() {
    let mode: ResizeMode = "cover"
    XCTAssertEqual(mode, .cover)
  }

  // MARK: - ImageFormat

  func testImageFormat_knownValues() {
    XCTAssertEqual(ImageFormat.origin.rawValue, "origin")
    XCTAssertEqual(ImageFormat.webp.rawValue, "webp")
    XCTAssertEqual(ImageFormat.avif.rawValue, "avif")
  }

  func testImageFormat_customValue() {
    let custom = ImageFormat(rawValue: "jpeg")
    XCTAssertEqual(custom.rawValue, "jpeg")
  }

  func testImageFormat_stringLiteral() {
    let format: ImageFormat = "webp"
    XCTAssertEqual(format, .webp)
  }

  // MARK: - SortOrder

  func testSortOrder_knownValues() {
    XCTAssertEqual(Storage.SortOrder.ascending.rawValue, "asc")
    XCTAssertEqual(Storage.SortOrder.descending.rawValue, "desc")
  }

  func testSortOrder_encodes_asRawValue() throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(Storage.SortOrder.ascending)
    let string = String(data: data, encoding: .utf8)
    XCTAssertEqual(string, "\"asc\"")
  }

  func testSortOrder_decodes_fromRawValue() throws {
    let data = "\"desc\"".data(using: .utf8)!
    let order = try JSONDecoder().decode(Storage.SortOrder.self, from: data)
    XCTAssertEqual(order, .descending)
  }
}
