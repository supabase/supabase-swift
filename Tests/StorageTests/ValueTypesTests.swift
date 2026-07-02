import Foundation
import Testing

@testable import Storage

// MARK: - StorageByteCount

@Suite struct StorageByteCountTests {
  @Test func bytes() {
    #expect(StorageByteCount.bytes(1024).bytes == 1024)
  }

  @Test func kilobytes() {
    #expect(StorageByteCount.kilobytes(10).bytes == 10_240)
  }

  @Test func megabytes() {
    #expect(StorageByteCount.megabytes(5).bytes == 5_242_880)
  }

  @Test func gigabytes() {
    #expect(StorageByteCount.gigabytes(1).bytes == 1_073_741_824)
  }

  @Test func integerLiteral() {
    let count: StorageByteCount = 2048
    #expect(count.bytes == 2048)
  }

  @Test func equality() {
    #expect(StorageByteCount.megabytes(1) == StorageByteCount(1_048_576))
  }
}

// MARK: - ResizeMode

@Suite struct ResizeModeTests {
  @Test func staticConstants() {
    #expect(ResizeMode.cover.rawValue == "cover")
    #expect(ResizeMode.contain.rawValue == "contain")
    #expect(ResizeMode.fill.rawValue == "fill")
  }

  @Test func stringLiteral() {
    let mode: ResizeMode = "cover"
    #expect(mode == .cover)
  }

  @Test func customValue() {
    let mode = ResizeMode(rawValue: "custom")
    #expect(mode.rawValue == "custom")
  }

  @Test func encodes() throws {
    let encoded = try JSONEncoder().encode(ResizeMode.cover)
    #expect(String(data: encoded, encoding: .utf8) == "\"cover\"")
  }

  @Test func decodes() throws {
    let data = "\"contain\"".data(using: .utf8)!
    let mode = try JSONDecoder().decode(ResizeMode.self, from: data)
    #expect(mode == .contain)
  }
}

// MARK: - ImageFormat

@Suite struct ImageFormatTests {
  @Test func staticConstants() {
    #expect(ImageFormat.origin.rawValue == "origin")
    #expect(ImageFormat.webp.rawValue == "webp")
    #expect(ImageFormat.avif.rawValue == "avif")
  }

  @Test func stringLiteral() {
    let format: ImageFormat = "webp"
    #expect(format == .webp)
  }

  @Test func encodes() throws {
    let encoded = try JSONEncoder().encode(ImageFormat.webp)
    #expect(String(data: encoded, encoding: .utf8) == "\"webp\"")
  }

  @Test func decodes() throws {
    let data = "\"avif\"".data(using: .utf8)!
    let format = try JSONDecoder().decode(ImageFormat.self, from: data)
    #expect(format == .avif)
  }
}

// MARK: - SortOrder

@Suite struct SortOrderTests {
  @Test func staticConstants() {
    #expect(Storage.SortOrder.ascending.rawValue == "asc")
    #expect(Storage.SortOrder.descending.rawValue == "desc")
  }

  @Test func stringLiteral() {
    let order: Storage.SortOrder = "asc"
    #expect(order == .ascending)
  }

  @Test func encodes() throws {
    let encoded = try JSONEncoder().encode(Storage.SortOrder.descending)
    #expect(String(data: encoded, encoding: .utf8) == "\"desc\"")
  }
}

// MARK: - DownloadBehavior

@Suite struct DownloadBehaviorTests {
  @Test func withOriginalNameQueryValue() {
    #expect(DownloadBehavior.withOriginalName.queryValue == "")
  }

  @Test func namedQueryValue() {
    #expect(DownloadBehavior.named("report.pdf").queryValue == "report.pdf")
  }
}
