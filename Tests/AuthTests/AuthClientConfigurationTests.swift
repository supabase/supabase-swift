//
//  AuthClientConfigurationTests.swift
//
//
//  Created by Guilherme Souza on 13/08/26.
//

import Foundation
import Logging
import TestHelpers
import Testing

@testable import Auth

@Suite
struct AuthClientConfigurationTests {
  @Test
  func loggerIsTaggedWithSystemMetadata() {
    let configuration = AuthClient.Configuration(
      url: URL(string: "http://localhost")!,
      localStorage: InMemoryLocalStorage(),
      logger: Logging.Logger(label: "test")
    )

    #expect(configuration.logger[metadataKey: "system"] == "auth")
  }

  @Test
  func loggerKeepsSystemTagAlongsideClientIDTag() {
    let configuration = AuthClient.Configuration(
      url: URL(string: "http://localhost")!,
      localStorage: InMemoryLocalStorage(),
      logger: Logging.Logger(label: "test")
    )

    let sut = AuthClient(configuration: configuration)
    let dependenciesLogger = sut.dependencies.logger

    #expect(dependenciesLogger[metadataKey: "system"] == "auth")
    #expect(dependenciesLogger[metadataKey: "client_id"] != nil)
  }

  @Test
  func loggerRedactsSecretsBeforeTheCallersHandlerSeesThem() {
    let recorder = LogRecorder()
    let configuration = AuthClient.Configuration(
      url: URL(string: "http://localhost")!,
      localStorage: InMemoryLocalStorage(),
      logger: recorder.makeLogger()
    )

    configuration.logger.warning("refresh failed: refresh_token=r-secret-1")

    #expect(recorder.entries == ["refresh failed: refresh_token=<redacted> system=auth"])
  }
}
