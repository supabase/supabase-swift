import Foundation
import Testing

@testable import RealtimeV2

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct RealtimeClientOptionsTests {
  @Test
  func sessionDefaultsToNil() {
    let options = RealtimeClientOptions(headers: ["apikey": "test-key"])
    #expect(options.session == nil)
  }

  @Test
  func sessionCanBeOverridden() {
    let customSession = URLSession(configuration: .ephemeral)
    let options = RealtimeClientOptions(
      headers: ["apikey": "test-key"],
      session: customSession
    )
    #expect(options.session === customSession)
  }
}
