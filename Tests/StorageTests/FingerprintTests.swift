import Foundation
import Testing

@testable import Storage

@Suite
struct FingerprintTests {
  @Test
  func acceptsSixtyFourLowercaseHexCharacters() {
    let rawValue = String(repeating: "0123456789abcdef", count: 4)

    #expect(Fingerprint(rawValue: rawValue)?.rawValue == rawValue)
  }

  @Test(arguments: [
    "",
    "f1",
    String(repeating: "a", count: 63),
    String(repeating: "a", count: 65),
    String(repeating: "A", count: 64),
    String(repeating: "g", count: 64),
    String(repeating: "a", count: 62) + "..",
    String(repeating: "a", count: 63) + "/",
  ])
  func rejectsAnyOtherString(_ rawValue: String) {
    #expect(Fingerprint(rawValue: rawValue) == nil)
  }

  @Test
  func parsesOnlyRecordFileNames() {
    let fingerprint = Fingerprint.repeating("c")

    #expect(Fingerprint(recordFileName: "\(fingerprint.rawValue).json") == fingerprint)
    #expect(Fingerprint(recordFileName: "\(fingerprint.rawValue).bin") == nil)
    #expect(Fingerprint(recordFileName: fingerprint.rawValue) == nil)
    #expect(Fingerprint(recordFileName: "settings.json") == nil)
    #expect(Fingerprint(recordFileName: "\(fingerprint.rawValue.uppercased()).json") == nil)
  }

  @Test
  func codesAsASingleString() throws {
    let fingerprint = Fingerprint.repeating("c")

    let data = try JSONEncoder().encode(fingerprint)

    #expect(String(decoding: data, as: UTF8.self) == "\"\(fingerprint.rawValue)\"")
    #expect(try JSONDecoder().decode(Fingerprint.self, from: data) == fingerprint)
  }

  @Test
  func decodingAMalformedValueThrows() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(Fingerprint.self, from: Data("\"f1\"".utf8))
    }
  }
}
