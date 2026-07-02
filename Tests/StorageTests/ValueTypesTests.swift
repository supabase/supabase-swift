import Foundation
import XCTest

@testable import Storage

// MARK: - StorageByteCount

final class StorageByteCountTests: XCTestCase {
  func testIntegerInit() {
    let count = StorageByteCount(5_000_000)
    XCTAssertEqual(count.intValue, 5_000_000)
  }

  func testIntegerLiteral() {
    let count: StorageByteCount = 2048
    XCTAssertEqual(count.intValue, 2048)
  }

  func testEquality() {
    XCTAssertEqual(StorageByteCount(1_000_000), StorageByteCount(1_000_000))
  }

  func testKilobytes() {
    let count = StorageByteCount.kilobytes(500)
    XCTAssertNil(count.intValue)
    XCTAssertEqual(count.stringValue, "500kb")
  }

  func testMegabytes() {
    let count = StorageByteCount.megabytes(1.5)
    XCTAssertNil(count.intValue)
    XCTAssertEqual(count.stringValue, "1.5mb")
  }

  func testGigabytes() {
    let count = StorageByteCount.gigabytes(2)
    XCTAssertNil(count.intValue)
    XCTAssertEqual(count.stringValue, "2gb")
  }

  func testStringLiteralNumeric() {
    let count: StorageByteCount = "1000000"
    XCTAssertEqual(count.intValue, 1_000_000)
  }

  func testStringLiteralHumanReadable() {
    let count: StorageByteCount = "1mb"
    XCTAssertNil(count.intValue)
  }

  func testEncodesAsNumber() throws {
    let encoded = try JSONEncoder().encode(StorageByteCount(1_000_000))
    let json = String(decoding: encoded, as: UTF8.self)
    XCTAssertEqual(json, "1000000")
  }

  func testEncodesAsString() throws {
    let count: StorageByteCount = "1mb"
    let encoded = try JSONEncoder().encode(count)
    let json = String(decoding: encoded, as: UTF8.self)
    XCTAssertEqual(json, "\"1mb\"")
  }
}

// MARK: - ResizeMode

final class ResizeModeTests: XCTestCase {
  func testStaticConstants() {
    XCTAssertEqual(ResizeMode.cover.rawValue, "cover")
    XCTAssertEqual(ResizeMode.contain.rawValue, "contain")
    XCTAssertEqual(ResizeMode.fill.rawValue, "fill")
  }

  func testStringLiteral() {
    let mode: ResizeMode = "cover"
    XCTAssertEqual(mode, .cover)
  }

  func testCustomValue() {
    let mode = ResizeMode(rawValue: "custom")
    XCTAssertEqual(mode.rawValue, "custom")
  }

  func testEncodes() throws {
    let encoded = try JSONEncoder().encode(ResizeMode.cover)
    XCTAssertEqual(String(data: encoded, encoding: .utf8), "\"cover\"")
  }

  func testDecodes() throws {
    let data = "\"contain\"".data(using: .utf8)!
    let mode = try JSONDecoder().decode(ResizeMode.self, from: data)
    XCTAssertEqual(mode, .contain)
  }
}

// MARK: - ImageFormat

final class ImageFormatTests: XCTestCase {
  func testStaticConstants() {
    XCTAssertEqual(ImageFormat.origin.rawValue, "origin")
    XCTAssertEqual(ImageFormat.webp.rawValue, "webp")
    XCTAssertEqual(ImageFormat.avif.rawValue, "avif")
  }

  func testStringLiteral() {
    let format: ImageFormat = "webp"
    XCTAssertEqual(format, .webp)
  }

  func testEncodes() throws {
    let encoded = try JSONEncoder().encode(ImageFormat.webp)
    XCTAssertEqual(String(data: encoded, encoding: .utf8), "\"webp\"")
  }

  func testDecodes() throws {
    let data = "\"avif\"".data(using: .utf8)!
    let format = try JSONDecoder().decode(ImageFormat.self, from: data)
    XCTAssertEqual(format, .avif)
  }
}

// MARK: - SortOrder

final class SortOrderTests: XCTestCase {
  func testStaticConstants() {
    XCTAssertEqual(Storage.SortOrder.ascending.rawValue, "asc")
    XCTAssertEqual(Storage.SortOrder.descending.rawValue, "desc")
  }

  func testStringLiteral() {
    let order: Storage.SortOrder = "asc"
    XCTAssertEqual(order, .ascending)
  }

  func testEncodes() throws {
    let encoded = try JSONEncoder().encode(Storage.SortOrder.descending)
    XCTAssertEqual(String(data: encoded, encoding: .utf8), "\"desc\"")
  }
}

// MARK: - DownloadBehavior

final class DownloadBehaviorValueTests: XCTestCase {
  func testWithOriginalNameQueryValue() {
    XCTAssertEqual(DownloadBehavior.withOriginalName.queryValue, "")
  }

  func testNamedQueryValue() {
    XCTAssertEqual(DownloadBehavior.named("report.pdf").queryValue, "report.pdf")
  }
}
