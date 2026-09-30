import Foundation
import Logging
import Testing

@testable import PostgREST

@Suite
struct PostgrestClientConfigurationTests {
  @Test
  func loggerIsTaggedWithSystemMetadata() {
    let configuration = PostgrestClient.Configuration(
      url: URL(string: "http://localhost")!,
      logger: Logging.Logger(label: "test")
    )

    #expect(configuration.logger[metadataKey: "system"] == "postgrest")
  }
}
