import Storage
import Testing

@Suite
struct FileOptionsTests {
  @Test
  func defaultInitialization() {
    let options = FileOptions()

    #expect(options.cacheControl == "3600")
    #expect(options.contentType == nil)
    #expect(options.upsert == false)
    #expect(options.metadata == nil)
  }

  @Test
  func customInitialization() {
    let metadata: [String: AnyJSON] = ["key": .string("value")]
    let options = FileOptions(
      cacheControl: "7200",
      contentType: "image/jpeg",
      upsert: true,
      metadata: metadata
    )

    #expect(options.cacheControl == "7200")
    #expect(options.contentType == "image/jpeg")
    #expect(options.upsert == true)
    #expect(options.metadata?["key"] == .string("value"))
  }
}
