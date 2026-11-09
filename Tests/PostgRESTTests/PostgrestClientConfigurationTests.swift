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

  @Test(arguments: [
    "project-ref", "https:///v1", "//project-ref.supabase.co/v1", "mailto:someone@example.com",
  ])
  func initThrowsWhenTheURLHasNoSchemeOrHost(url: String) throws {
    let url = try #require(URL(string: url))
    let error = #expect(throws: PostgrestError.self) {
      try PostgrestClient(url: url)
    }
    #expect(error?.kind == .invalidConfiguration)
  }
}
