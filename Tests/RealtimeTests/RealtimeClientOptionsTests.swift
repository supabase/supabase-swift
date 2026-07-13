import Foundation
import Testing

@testable import RealtimeV2

@Suite
struct RealtimeClientOptionsTests {
  @Test
  func sessionDefaultsToShared() {
    let options = RealtimeClientOptions(headers: ["apikey": "test-key"])
    #expect(options.session === URLSession.shared)
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
