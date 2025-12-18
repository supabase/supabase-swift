import Testing

@testable import Storage

@Suite
struct TransformOptionsTests {
  @Test
  func defaultInitialization() {
    let options = TransformOptions()

    #expect(options.width == nil)
    #expect(options.height == nil)
    #expect(options.resize == nil)
    #expect(options.quality == 80)
    #expect(options.format == nil)
  }

  @Test
  func customInitialization() {
    let options = TransformOptions(
      width: 100,
      height: 200,
      resize: "cover",
      quality: 90,
      format: "webp"
    )

    #expect(options.width == 100)
    #expect(options.height == 200)
    #expect(options.resize == "cover")
    #expect(options.quality == 90)
    #expect(options.format == "webp")
  }

  @Test
  func queryItemsGeneration() {
    let options = TransformOptions(
      width: 100,
      height: 200,
      resize: "cover",
      quality: 90,
      format: "webp"
    )

    let queryItems = options.queryItems
    let query: [String: String] = Dictionary(
      uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

    #expect(queryItems.count == 5)
    #expect(query["width"] == "100")
    #expect(query["height"] == "200")
    #expect(query["resize"] == "cover")
    #expect(query["quality"] == "90")
    #expect(query["format"] == "webp")
  }

  @Test
  func partialQueryItemsGeneration() {
    let options = TransformOptions(width: 100, quality: 75)
    let queryItems = options.queryItems
    let query: [String: String] = Dictionary(
      uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

    #expect(queryItems.count == 2)
    #expect(query["width"] == "100")
    #expect(query["quality"] == "75")
  }
}
