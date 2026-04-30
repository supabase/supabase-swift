import Foundation
import Testing

@testable import Storage

@Suite
struct ValueTypesTests {

  // MARK: - ResizeMode

  @Test func resizeMode_knownValues() {
    #expect(ResizeMode.cover.rawValue == "cover")
    #expect(ResizeMode.contain.rawValue == "contain")
    #expect(ResizeMode.fill.rawValue == "fill")
  }

  @Test func resizeMode_customValue() {
    let custom = ResizeMode(rawValue: "fit")
    #expect(custom.rawValue == "fit")
  }

  @Test func resizeMode_stringLiteral() {
    let mode: ResizeMode = "cover"
    #expect(mode == .cover)
  }

  // MARK: - ImageFormat

  @Test func imageFormat_knownValues() {
    #expect(ImageFormat.origin.rawValue == "origin")
    #expect(ImageFormat.webp.rawValue == "webp")
    #expect(ImageFormat.avif.rawValue == "avif")
  }

  @Test func imageFormat_customValue() {
    let custom = ImageFormat(rawValue: "jpeg")
    #expect(custom.rawValue == "jpeg")
  }

  @Test func imageFormat_stringLiteral() {
    let format: ImageFormat = "webp"
    #expect(format == .webp)
  }

  // MARK: - SortOrder

  @Test func sortOrder_knownValues() {
    #expect(Storage.SortOrder.ascending.rawValue == "asc")
    #expect(Storage.SortOrder.descending.rawValue == "desc")
  }

  @Test func sortOrder_encodesAsRawValue() throws {
    let data = try JSONEncoder().encode(Storage.SortOrder.ascending)
    let string = String(data: data, encoding: .utf8)
    #expect(string == "\"asc\"")
  }

  @Test func sortOrder_decodesFromRawValue() throws {
    let data = Data("\"desc\"".utf8)
    let order = try JSONDecoder().decode(Storage.SortOrder.self, from: data)
    #expect(order == .descending)
  }

  // MARK: - DownloadBehavior

  @Test func downloadBehavior_withOriginalName() {
    if case .withOriginalName = DownloadBehavior.withOriginalName {
    } else {
      Issue.record("Expected .withOriginalName case")
    }
  }

  @Test func downloadBehavior_named() {
    if case .named(let name) = DownloadBehavior.named("report.pdf") {
      #expect(name == "report.pdf")
    } else {
      Issue.record("Expected .named case")
    }
  }

  // MARK: - SortBy

  @Test func sortBy_encodesOrderAsRawValue() throws {
    let sortBy = SortBy(column: "name", order: .descending)
    let encoder = JSONEncoder()
    let data = try encoder.encode(sortBy)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["column"] as? String == "name")
    #expect(json["order"] as? String == "desc")
  }
}
