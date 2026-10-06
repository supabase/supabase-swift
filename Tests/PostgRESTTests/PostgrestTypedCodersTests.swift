//
//  PostgrestTypedCodersTests.swift
//  PostgREST
//
//  Created by Guilherme Souza on 06/10/26.
//

import Foundation
import Testing

@testable import PostgREST

/// The typed API derives column names from `CodingKeys`, so a key strategy on a configured coder
/// must never reach it.
@Suite
struct PostgrestTypedCodersTests {
  struct Todo: PostgrestWritableRelation {
    static let relationName = "todos"
    static let selectString = "id,is_done"

    var id: Int
    var isDone: Bool

    enum CodingKeys: String, CodingKey {
      case id
      case isDone = "is_done"
    }

    struct Columns: Sendable {
      let id = PostgrestColumn<Todo, Int>("id")
      let isDone = PostgrestColumn<Todo, Bool>("is_done")
      /// Spelled in camelCase on purpose: a configured `.convertToSnakeCase` encoder would send
      /// it as `due_at`, so the body shows which encoder ran.
      let dueAt = PostgrestColumn<Todo, Int>("dueAt")
    }

    static let columns = Columns()

    /// No `CodingKeys`, on purpose: the fixed encoder writes `isDone`, while a configured
    /// `.convertToSnakeCase` encoder would write `is_done`, so the body shows which one ran.
    struct Draft: Encodable, Sendable {
      var isDone: Bool
    }
  }

  private static func snakeCaseCapture(body: String = "[]") -> QueryCapture {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return QueryCapture(body: body, encoder: encoder, decoder: decoder)
  }

  @Test
  func selectIgnoresTheConfiguredDecoder() async throws {
    let capture = Self.snakeCaseCapture(body: #"[{"id":1,"is_done":true}]"#)
    let rows = try await capture.client.from(Todo.self).select().execute().value
    // `.convertFromSnakeCase` would look for the key "isDone" and fail on "is_done".
    #expect(rows.first?.isDone == true)
  }

  @Test
  func insertIgnoresTheConfiguredEncoder() async throws {
    let capture = Self.snakeCaseCapture()
    try await capture.client.from(Todo.self).insert(.init(isDone: true)).execute()
    #expect(capture.bodyString == #"{"isDone":true}"#)
  }

  @Test
  func updateIgnoresTheConfiguredEncoder() async throws {
    let capture = Self.snakeCaseCapture()
    try await capture.client.from(Todo.self).update { $0.dueAt = 3 }.all().execute()
    #expect(capture.bodyString == #"{"dueAt":3}"#)
  }
}
