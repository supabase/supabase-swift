import Foundation
import Testing

@testable import Storage

@Suite
struct ByteCountTests {
  @Test
  func bytesAndLiterals() {
    #expect(ByteCount(bytes: 5_000_000).rawValue == "5000000")
    #expect(ByteCount(bytes: 5_000_000).bytes == 5_000_000)
    let integer: ByteCount = 2048
    #expect(integer.bytes == 2048)
    let numericString: ByteCount = "1000000"
    #expect(numericString.bytes == 1_000_000)
    let humanReadable: ByteCount = "1.5mb"
    #expect(humanReadable.bytes == nil)
    #expect(humanReadable.rawValue == "1.5mb")
  }

  @Test
  func unitsKeepTheServerSpelling() {
    #expect(ByteCount.kilobytes(500).rawValue == "500kb")
    #expect(ByteCount.megabytes(1.5).rawValue == "1.5mb")
    #expect(ByteCount.gigabytes(2).rawValue == "2gb")
    #expect(ByteCount.gigabytes(1e19).rawValue == "1e+19gb")
  }

  @Test
  func encodesANumberOrAString() throws {
    #expect(
      try String(decoding: JSONEncoder().encode(ByteCount(bytes: 1_000_000)), as: UTF8.self)
        == "1000000")
    #expect(
      try String(decoding: JSONEncoder().encode(ByteCount.megabytes(1)), as: UTF8.self) == "\"1mb\""
    )
  }
}

@Suite
struct ObjectSortColumnTests {
  @Test
  func staticConstants() {
    #expect(ObjectSortColumn.name.rawValue == "name")
    #expect(ObjectSortColumn.updatedAt.rawValue == "updated_at")
    #expect(ObjectSortColumn.createdAt.rawValue == "created_at")
    #expect(ObjectSortColumn.lastAccessedAt.rawValue == "last_accessed_at")
  }
}

@Suite
struct VersionFilterTests {
  @Test
  func staticConstants() {
    #expect(VersionFilter.exclude.rawValue == "exclude")
    #expect(VersionFilter.include.rawValue == "include")
    #expect(VersionFilter.only.rawValue == "only")
  }
}

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
