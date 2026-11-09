//
//  PostgrestQueryFixture.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import Foundation
import PostgREST
import TestHelpers

struct PostgrestQueryFixture {
  static let url = URL(string: "http://localhost:54321/rest/v1")!

  var url: URL { Self.url }

  let transport = RecordingTransport()
  let sut: PostgrestClient

  init() throws {
    sut = try PostgrestClient(
      configuration: .init(
        url: Self.url,
        headers: [
          .apikey:
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
        ],
        http: .init(transport: transport),
        encoder: {
          let encoder = JSONEncoder.supabase()
          encoder.outputFormatting = [.sortedKeys]
          return encoder
        }()
      )
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
