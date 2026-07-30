import Foundation
import Testing

@testable import Storage

// MARK: - StorageByteCount

@Suite
struct StorageByteCountTests {
  @Test
  func integerInit() {
    let count = StorageByteCount(5_000_000)
    #expect(count.intValue == 5_000_000)
  }

  @Test
  func integerLiteral() {
    let count: StorageByteCount = 2048
    #expect(count.intValue == 2048)
  }

  @Test
  func equality() {
    #expect(StorageByteCount(1_000_000) == StorageByteCount(1_000_000))
  }

  @Test
  func kilobytes() {
    let count = StorageByteCount.kilobytes(500)
    #expect(count.intValue == nil)
    #expect(count.stringValue == "500kb")
  }

  @Test
  func megabytes() {
    let count = StorageByteCount.megabytes(1.5)
    #expect(count.intValue == nil)
    #expect(count.stringValue == "1.5mb")
  }

  @Test
  func gigabytes() {
    let count = StorageByteCount.gigabytes(2)
    #expect(count.intValue == nil)
    #expect(count.stringValue == "2gb")
  }

  @Test
  func stringLiteralNumeric() {
    let count: StorageByteCount = "1000000"
    #expect(count.intValue == 1_000_000)
  }

  @Test
  func stringLiteralHumanReadable() {
    let count: StorageByteCount = "1mb"
    #expect(count.intValue == nil)
  }

  @Test
  func encodesAsNumber() throws {
    let encoded = try JSONEncoder().encode(StorageByteCount(1_000_000))
    let json = String(decoding: encoded, as: UTF8.self)
    #expect(json == "1000000")
  }

  @Test
  func encodesAsString() throws {
    let count: StorageByteCount = "1mb"
    let encoded = try JSONEncoder().encode(count)
    let json = String(decoding: encoded, as: UTF8.self)
    #expect(json == "\"1mb\"")
  }

  @Test
  func gigabytesWholeValueOutsideInt64Range() {
    let count = StorageByteCount.gigabytes(1e19)
    #expect(count.stringValue == "1e+19gb")
  }
}

// MARK: - SortBy

@Suite
struct SortByTests {
  @Test
  func initWithDefaultedOrder() {
    let sortBy = SortBy(column: "name")
    #expect(sortBy.column == "name")
    #expect(sortBy.order == nil)
  }

  @Test
  func initWithSortOrder() {
    let sortBy = SortBy(column: "name", order: .ascending)
    #expect(sortBy.order == "asc")
  }

  @Test
  func deprecatedInitWithStringVariable() {
    let order: String? = "desc"
    let sortBy = SortBy(column: "name", order: order)
    #expect(sortBy.order == "desc")
  }

  @Test
  func deprecatedInitWithOrderVariableOnly() {
    let order: String? = "asc"
    let sortBy = SortBy(order: order)
    #expect(sortBy.column == nil)
    #expect(sortBy.order == "asc")
  }
}

// MARK: - ResizeMode

@Suite
struct ResizeModeTests {
  @Test
  func staticConstants() {
    #expect(ResizeMode.cover.rawValue == "cover")
    #expect(ResizeMode.contain.rawValue == "contain")
    #expect(ResizeMode.fill.rawValue == "fill")
  }

  @Test
  func stringLiteral() {
    let mode: ResizeMode = "cover"
    #expect(mode == .cover)
  }

  @Test
  func customValue() {
    let mode = ResizeMode(rawValue: "custom")
    #expect(mode.rawValue == "custom")
  }

  @Test
  func encodes() throws {
    let encoded = try JSONEncoder().encode(ResizeMode.cover)
    #expect(String(data: encoded, encoding: .utf8) == "\"cover\"")
  }

  @Test
  func decodes() throws {
    let data = "\"contain\"".data(using: .utf8)!
    let mode = try JSONDecoder().decode(ResizeMode.self, from: data)
    #expect(mode == .contain)
  }
}

// MARK: - ImageFormat

@Suite
struct ImageFormatTests {
  @Test
  func staticConstants() {
    #expect(ImageFormat.origin.rawValue == "origin")
    #expect(ImageFormat.webp.rawValue == "webp")
    #expect(ImageFormat.avif.rawValue == "avif")
  }

  @Test
  func stringLiteral() {
    let format: ImageFormat = "webp"
    #expect(format == .webp)
  }

  @Test
  func encodes() throws {
    let encoded = try JSONEncoder().encode(ImageFormat.webp)
    #expect(String(data: encoded, encoding: .utf8) == "\"webp\"")
  }

  @Test
  func decodes() throws {
    let data = "\"avif\"".data(using: .utf8)!
    let format = try JSONDecoder().decode(ImageFormat.self, from: data)
    #expect(format == .avif)
  }
}

// MARK: - SortOrder

@Suite
struct SortOrderTests {
  @Test
  func staticConstants() {
    #expect(Storage.SortOrder.ascending.rawValue == "asc")
    #expect(Storage.SortOrder.descending.rawValue == "desc")
  }

  @Test
  func stringLiteral() {
    let order: Storage.SortOrder = "asc"
    #expect(order == .ascending)
  }

  @Test
  func encodes() throws {
    let encoded = try JSONEncoder().encode(Storage.SortOrder.descending)
    #expect(String(data: encoded, encoding: .utf8) == "\"desc\"")
  }
}

// MARK: - DownloadBehavior

@Suite
struct DownloadBehaviorValueTests {
  @Test
  func withOriginalNameQueryValue() {
    #expect(DownloadBehavior.withOriginalName.queryValue == "")
  }

  @Test
  func namedQueryValue() {
    #expect(DownloadBehavior.named("report.pdf").queryValue == "report.pdf")
  }
}
