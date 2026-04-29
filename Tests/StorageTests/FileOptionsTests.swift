import Testing

@testable import Storage

@Suite
struct FileOptionsTests {

  @Test func defaultInitialization() {
    let options = FileOptions()

    #expect(options.cacheControl == "3600")
    #expect(options.contentType == nil)
    #expect(!options.upsert)
    #expect(options.metadata == nil)
  }

  @Test func customInitialization() {
    let options = FileOptions(
      cacheControl: "7200",
      contentType: "image/jpeg",
      upsert: true,
      metadata: ["key": .string("value")]
    )

    #expect(options.cacheControl == "7200")
    #expect(options.contentType == "image/jpeg")
    #expect(options.upsert)
    #expect(options.metadata?["key"] == .string("value"))
  }
}
