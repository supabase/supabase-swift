import Foundation
import Logging
import Testing

@testable import PostgREST

@Suite
struct PostgrestClientConfigurationTests {
  private let url = URL(string: "http://localhost")!

  @Test
  func loggerIsTaggedWithSystemMetadata() {
    let configuration = PostgrestClient.Configuration(
      url: url,
      logger: Logging.Logger(label: "test")
    )

    #expect(configuration.logger[metadataKey: "system"] == "postgrest")
  }

  @Test
  func everyFieldIsMutable() {
    var configuration = PostgrestClient.Configuration(url: url)
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    configuration.encoder = encoder
    configuration.decoder = decoder
    configuration.logger = Logging.Logger(label: "replaced")
    configuration.clock = SuspendingClock()

    #expect(configuration.encoder === encoder)
    #expect(configuration.decoder === decoder)
    #expect(configuration.logger.label == "replaced")
    #expect(configuration.clock is SuspendingClock)
  }

  @Test
  func schemaKeepsTheClock() {
    let client = PostgrestClient(configuration: .init(url: url, clock: SuspendingClock()))

    let scoped = client.schema("other")

    #expect(scoped.configuration.schema == "other")
    #expect(scoped.configuration.clock is SuspendingClock)
  }
}
