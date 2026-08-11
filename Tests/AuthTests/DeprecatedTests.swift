//
//  DeprecatedTests.swift
//
//
//  Created by Guilherme Souza on 04/08/26.
//

import Foundation
import TestHelpers
import Testing

@testable import Auth

/// Compile coverage for the deprecated single-codec `encoder`/`decoder` initializer
/// overloads, so a future change can't silently drop one of them. The deprecation
/// warnings these calls produce are expected and intentional.
@Suite
struct DeprecatedTests {
  @Test
  func configurationInitWithEncoderOnlyUsesDefaultDecoder() {
    let encoder = JSONEncoder()

    // `logger:` only exists on the new-style signature, forcing overload resolution to
    // this initializer instead of the older, narrower `logger`-less legacy overload.
    let configuration = AuthClient.Configuration(
      url: clientURL,
      localStorage: InMemoryLocalStorage(),
      logger: nil,
      encoder: encoder
    )

    #expect(configuration.resolvedEncoder === encoder)
    #expect(configuration.resolvedDecoder === AuthClient.Configuration.jsonDecoder)
  }

  @Test
  func configurationInitWithDecoderOnlyUsesDefaultEncoder() {
    let decoder = JSONDecoder()

    let configuration = AuthClient.Configuration(
      url: clientURL,
      localStorage: InMemoryLocalStorage(),
      logger: nil,
      decoder: decoder
    )

    #expect(configuration.resolvedEncoder === AuthClient.Configuration.jsonEncoder)
    #expect(configuration.resolvedDecoder === decoder)
  }

  @Test
  func authClientInitWithEncoderOnlyUsesDefaultDecoder() {
    let encoder = JSONEncoder()

    let sut = AuthClient(
      url: clientURL,
      localStorage: InMemoryLocalStorage(),
      logger: nil,
      encoder: encoder
    )

    #expect(Dependencies[sut.clientID].configuration.resolvedEncoder === encoder)
    #expect(
      Dependencies[sut.clientID].configuration.resolvedDecoder
        === AuthClient.Configuration
        .jsonDecoder
    )
  }

  @Test
  func authClientInitWithDecoderOnlyUsesDefaultEncoder() {
    let decoder = JSONDecoder()

    let sut = AuthClient(
      url: clientURL,
      localStorage: InMemoryLocalStorage(),
      logger: nil,
      decoder: decoder
    )

    #expect(
      Dependencies[sut.clientID].configuration.resolvedEncoder
        === AuthClient.Configuration
        .jsonEncoder
    )
    #expect(Dependencies[sut.clientID].configuration.resolvedDecoder === decoder)
  }
}
