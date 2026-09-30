import Foundation
import Logging
import Testing

@testable import Storage

@Suite
struct StorageClientConfigurationTests {
  @Test
  func loggerIsTaggedWithSystemMetadata() {
    let configuration = StorageClientConfiguration(
      url: URL(string: "http://localhost")!,
      headers: [:],
      logger: Logging.Logger(label: "test")
    )

    #expect(configuration.logger[metadataKey: "system"] == "storage")
  }
}
