//
//  PostgrestQueryTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import InlineSnapshotTesting
import Mocker
import PostgREST
import TestHelpers
import XCTest

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

class PostgrestQueryTests: XCTestCase {
  let url = URL(string: "http://localhost:54321/rest/v1")!

  let sessionConfiguration: URLSessionConfiguration = {
    let configuration = URLSessionConfiguration.default
    configuration.protocolClasses = [MockingURLProtocol.self]
    return configuration
  }()

  lazy var session = URLSession(configuration: sessionConfiguration)

  lazy var sut = PostgrestClient(
    url: url,
    headers: [
      "apikey":
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    ],
    logger: nil,
    fetch: { [session] in
      try await session.data(for: $0)
    },
    encoder: {
      let encoder = PostgrestClient.Configuration.jsonEncoder
      encoder.outputFormatting = [.sortedKeys]
      return encoder
    }()
  )

  struct User: Codable {
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
}
