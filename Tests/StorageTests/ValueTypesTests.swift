import Foundation
import Testing

@testable import Storage

// MARK: - ByteCount

@Suite
struct ByteCountTests {
  @Test
  func bytesAndLiteral() {
    #expect(ByteCount(bytes: 5_000_000).bytes == 5_000_000)
    let literal: ByteCount = 2048
    #expect(literal.bytes == 2048)
    #expect(ByteCount(bytes: 1) == 1)
  }

  @Test
  func unitsAreBinary() {
    #expect(ByteCount.kilobytes(500).bytes == 512_000)
    #expect(ByteCount.megabytes(1).bytes == 1_048_576)
    #expect(ByteCount.gigabytes(2).bytes == 2_147_483_648)
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
    #expect(sortBy.order == .ascending)
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
