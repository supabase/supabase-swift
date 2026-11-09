import Foundation
import Logging
import Testing

@testable import PostgREST

@Suite
struct PostgrestClientConfigurationTests {
  private let url = URL(string: "http://localhost")!

  @Test
  func loggerSetAfterInitIsTaggedWithSystemMetadata() throws {
    var configuration = PostgrestClient.Configuration(url: url)
    configuration.logger = Logging.Logger(label: "test")

    let client = try PostgrestClient(configuration: configuration)

    #expect(client.configuration.logger[metadataKey: "system"] == "postgrest")
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
  func eachConfigurationGetsItsOwnDefaultCoders() {
    let first = PostgrestClient.Configuration(url: url)
    let second = PostgrestClient.Configuration(url: url)

    #expect(first.encoder !== second.encoder)
    #expect(first.decoder !== second.decoder)
  }

  @Test
  func schemaKeepsTheClock() throws {
    let client = try PostgrestClient(configuration: .init(url: url, clock: SuspendingClock()))

    let scoped = client.schema("other")

    #expect(scoped.configuration.schema == "other")
    #expect(scoped.configuration.clock is SuspendingClock)
  }

  @Test(arguments: [
    "project-ref", "https:///v1", "//project-ref.supabase.co/v1", "mailto:someone@example.com",
  ])
  func initThrowsWhenTheURLHasNoSchemeOrHost(url: String) throws {
    let url = try #require(URL(string: url))
    let error = #expect(throws: PostgrestError.self) {
      try PostgrestClient(configuration: .init(url: url))
    }
    #expect(error?.kind == .invalidConfiguration)
  }
}
