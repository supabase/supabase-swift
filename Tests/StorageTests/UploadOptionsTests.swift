import Testing

@testable import Storage

@Suite
struct UploadOptionsTests {
  @Test
  func defaultInitialization() {
    let options = UploadOptions()

    #expect(options.cacheControl == .maxAge(.seconds(3600)))
    #expect(options.cacheControl.rawValue == "max-age=3600")
    #expect(options.contentType == nil)
    #expect(!options.upsert)
    #expect(options.metadata == nil)
    #expect(options.headers.isEmpty)
  }

  @Test
  func customInitialization() {
    let metadata: [String: JSONValue] = ["key": .string("value")]
    let options = UploadOptions(
      contentType: "image/jpeg",
      cacheControl: .noCache,
      upsert: true,
      metadata: metadata,
      headers: [.init("X-Mode")!: "test"]
    )

    #expect(options.cacheControl == .noCache)
    #expect(options.contentType == "image/jpeg")
    #expect(options.upsert)
    #expect(options.metadata?["key"] == .string("value"))
    #expect(options.headers[.init("X-Mode")!] == "test")
  }
}

@Suite
struct CacheControlTests {
  @Test
  func maxAgeIsWholeSeconds() {
    #expect(CacheControl.maxAge(.seconds(14400)).rawValue == "max-age=14400")
    #expect(CacheControl.maxAge(.milliseconds(1500)).rawValue == "max-age=1")
    #expect(CacheControl.maxAge(.seconds(90)).rawValue == "max-age=90")
  }

  @Test
  func directivesAndLiterals() {
    #expect(CacheControl.noCache.rawValue == "no-cache")
    #expect(CacheControl.noStore.rawValue == "no-store")
    let custom: CacheControl = "max-age=60, s-maxage=3600"
    #expect(custom.rawValue == "max-age=60, s-maxage=3600")
  }
}
