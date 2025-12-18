import Foundation
import Testing

@testable import Storage

@Suite
struct StorageHelpersTests {
  @Test
  func encodeMetadata_encodesJSONObject() throws {
    let data = encodeMetadata(["k": .string("v"), "n": .integer(1)])
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(object?["k"] as? String == "v")
    #expect(object?["n"] as? Int == 1)
  }

  @Test
  func stringHelpers_fileNameAndPathExtension() {
    #expect("folder/file.txt".fileName == "file.txt")
    #expect("folder/file.txt".pathExtension == "txt")
  }

  @Test
  func mimeType_unknownExtension_defaultsToOctetStream() {
    #expect(mimeType(forPathExtension: "definitely-unknown-ext") == "application/octet-stream")
  }
}
