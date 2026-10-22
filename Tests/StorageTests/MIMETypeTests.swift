import Testing

@testable import Storage

@Suite
struct MIMETypeTests {
  @Test(arguments: [
    ("png", "image/png"),
    ("JPG", "image/jpeg"),
    ("jpeg", "image/jpeg"),
    ("pdf", "application/pdf"),
    ("json", "application/json"),
    ("txt", "text/plain"),
    ("mp4", "video/mp4"),
  ])
  func infersCommonExtensions(pathExtension: String, expected: String) {
    #expect(mimeType(forPathExtension: pathExtension) == expected)
  }

  @Test
  func unknownExtensionIsOctetStream() {
    #expect(mimeType(forPathExtension: "notarealextension") == "application/octet-stream")
    #expect(mimeType(forPathExtension: "") == "application/octet-stream")
  }

  @Test
  func fallbackTableCoversCommonExtensionsOnEveryPlatform() {
    #expect(commonMIMETypes.count >= 20)
    #expect(commonMIMETypes["png"] == "image/png")
    #expect(commonMIMETypes["csv"] == "text/csv")
    #expect(commonMIMETypes["heic"] == "image/heic")
  }
}
