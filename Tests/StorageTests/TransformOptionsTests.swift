import Foundation
import Testing

@testable import Storage

@Suite
struct TransformOptionsTests {

  @Test func defaultInitialization() {
    let options = TransformOptions()

    #expect(options.width == nil)
    #expect(options.height == nil)
    #expect(options.resize == nil)
    #expect(options.quality == nil)
    #expect(options.format == nil)
  }

  @Test func isEmpty_defaultOptions() {
    #expect(TransformOptions().isEmpty)
  }

  @Test func isEmpty_withWidth() {
    #expect(!TransformOptions(width: 200).isEmpty)
  }

  @Test func isEmpty_withHeight() {
    #expect(!TransformOptions(height: 300).isEmpty)
  }

  @Test func isEmpty_withResize() {
    #expect(!TransformOptions(resize: .cover).isEmpty)
  }

  @Test func isEmpty_withQuality() {
    #expect(!TransformOptions(quality: 90).isEmpty)
  }

  @Test func isEmpty_withFormat() {
    #expect(!TransformOptions(format: .webp).isEmpty)
  }

  @Test func customInitialization() {
    let options = TransformOptions(
      width: 100,
      height: 200,
      resize: .cover,
      quality: 90,
      format: .webp
    )

    #expect(options.width == 100)
    #expect(options.height == 200)
    #expect(options.resize == .cover)
    #expect(options.quality == 90)
    #expect(options.format == .webp)
  }

  @Test func queryItemsGeneration() {
    let options = TransformOptions(
      width: 100,
      height: 200,
      resize: .cover,
      quality: 90,
      format: .webp
    )

    let queryItems = options.queryItems

    #expect(queryItems.count == 5)
    #expect(queryItems[0].name == "width")
    #expect(queryItems[0].value == "100")
    #expect(queryItems[1].name == "height")
    #expect(queryItems[1].value == "200")
    #expect(queryItems[2].name == "resize")
    #expect(queryItems[2].value == "cover")
    #expect(queryItems[3].name == "quality")
    #expect(queryItems[3].value == "90")
    #expect(queryItems[4].name == "format")
    #expect(queryItems[4].value == "webp")
  }

  @Test func partialQueryItemsGeneration() {
    let options = TransformOptions(width: 100, quality: 75)

    let queryItems = options.queryItems

    #expect(queryItems.count == 2)
    #expect(queryItems[0].name == "width")
    #expect(queryItems[0].value == "100")
    #expect(queryItems[1].name == "quality")
    #expect(queryItems[1].value == "75")
  }
}
