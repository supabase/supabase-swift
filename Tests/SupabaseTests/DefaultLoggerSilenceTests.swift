import Foundation
import Logging
import Testing

@testable import Supabase

/// Without a supplied logger, every client is silent in every build configuration.
@Suite
struct DefaultLoggerSilenceTests {
  private let url = URL(string: "http://localhost:54321")!

  @Test
  func everyConfigurationDefaultsToASilentLogger() {
    let loggers: [Logging.Logger] = [
      SupabaseClient.Configuration.Global().logger,
      AuthClient.Configuration(url: url, storageKey: "test").logger,
      AuthAdminClient.Configuration(url: url, secretKey: "test").logger,
      PostgrestClient.Configuration(url: url).logger,
      StorageClient.Configuration(url: url).logger,
      FunctionsClient.Configuration(url: url).logger,
      RealtimeClient.Configuration(url: url).logger,
    ]

    for logger in loggers {
      #expect(logger.handler is SwiftLogNoOpLogHandler, "\(logger.label)")
      #expect(logger.logLevel == .critical, "\(logger.label)")
    }
  }

}
