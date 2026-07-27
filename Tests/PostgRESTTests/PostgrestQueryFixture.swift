//
//  PostgrestQueryFixture.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import Foundation
import Mocker
import PostgREST
import TestHelpers
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Shared serialization boundary for the Mocker-backed PostgREST test suites: Mocker's mock
/// registry is process-global, and these suites stub overlapping URLs (e.g. `users`, `rpc/*`), so
/// running them concurrently would let one suite's stub satisfy another's request. `.serialized`
/// on a suite applies recursively to its nested suites, so nesting all of them under this empty
/// namespace serializes them against each other within this target. Each nested suite also carries
/// `.mockerSerialized` (see `TestHelpers/MockerSerialization.swift`) to extend that guarantee
/// across test *targets* too -- StorageTests has its own Mocker-backed suites, and without it the
/// two targets' suites can still run concurrently with each other and race on Mocker's shared
/// registry.
@Suite(.serialized)
enum PostgrestMockerTests {}

/// Shared fixture for suites that exercise `PostgrestClient` against a Mocker-backed session.
///
/// Suites compose this instead of subclassing, since Swift Testing suites don't share instance
/// state through inheritance. Each suite creates its own `PostgrestQueryFixture` in its `init()`.
struct PostgrestQueryFixture {
  static let url = URL(string: "http://localhost:54321/rest/v1")!

  var url: URL { Self.url }

  let sut: PostgrestClient

  init() {
    let configuration = URLSessionConfiguration.default
    configuration.protocolClasses = [MockingURLProtocol.self]
    let session = URLSession(configuration: configuration)

    sut = PostgrestClient(
      url: Self.url,
      headers: [
        "apikey":
          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
      ],
      logger: nil,
      fetch: { try await session.data(for: $0) },
      encoder: {
        let encoder = PostgrestClient.Configuration.jsonEncoder
        encoder.outputFormatting = [.sortedKeys]
        return encoder
      }()
    )
  }
}

struct User: Codable, Sendable {
  let id: Int
  let username: String
}

struct Country: Decodable {
  let name: String
  let cities: [City]

  struct City: Decodable {
    let name: String
  }
}
