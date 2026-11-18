//
//  PostgrestTypedCodersTests.swift
//  PostgREST
//
//  Created by Guilherme Souza on 06/10/26.
//

import Foundation
import Testing

@_spi(Experimental) @testable import PostgREST

@Suite
struct PostgrestTypedCodersTests {
  struct Todo: _PostgrestWritableRelation {
    static let relationName = "todos"
    static let selectString = "id,is_done"

    var id: Int
    var isDone: Bool

    enum CodingKeys: String, CodingKey {
      case id
      case isDone = "is_done"
    }

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
      let isDone = _PostgrestColumn<Todo, Bool>("is_done")
      let dueAt = _PostgrestColumn<Todo, Int>("dueAt")
    }

    static let columns = Columns()

    struct Draft: Encodable, Sendable {
      var isDone: Bool
    }
  }

  struct Event: _PostgrestWritableRelation, _PostgrestKeyedRelation {
    static let relationName = "events"
    static let selectString = "id,starts_at"

    var id: Int
    var startsAt: Date

    enum CodingKeys: String, CodingKey {
      case id
      case startsAt = "starts_at"
    }

    struct Columns: Sendable {
      let id = _PostgrestColumn<Event, Int>("id")
      let startsAt = _PostgrestColumn<Event, Date>("starts_at")
    }

    static let columns = Columns()
    static let primaryKeyColumns = ["id"]

    struct Draft: Encodable, Sendable {
      var startsAt: Date

      enum CodingKeys: String, CodingKey {
        case startsAt = "starts_at"
      }
    }
  }

  struct EventsAfter: _PostgrestFunction {
    typealias Result = Date
    static let functionName = "events_after"
    var after: Date
  }

  private static let date = Date(timeIntervalSince1970: 1_000)

  /// Dates as seconds since 1970, which `JSONEncoder.supabase()` never writes. Pass
  /// `snakeCase: true` to add a key strategy the typed API must ignore.
  private static func secondsCapture(
    body: String = "[]",
    snakeCase: Bool = false
  ) throws -> QueryCapture {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    if snakeCase {
      encoder.keyEncodingStrategy = .convertToSnakeCase
      decoder.keyDecodingStrategy = .convertFromSnakeCase
    }
    return try QueryCapture(body: body, encoder: encoder, decoder: decoder)
  }

  @Test
  func selectUsesTheConfiguredDecoder() async throws {
    let capture = try Self.secondsCapture(body: #"[{"id":1,"starts_at":1000}]"#)
    let rows = try await capture.client.from(Event.self).select().execute().value
    #expect(rows.first?.startsAt == Self.date)
  }

  @Test
  func singleUsesTheConfiguredDecoder() async throws {
    let capture = try Self.secondsCapture(body: #"{"id":1,"starts_at":1000}"#)
    let row = try await capture.client.from(Event.self).select().single().execute().value
    #expect(row.startsAt == Self.date)
  }

  @Test
  func maybeSingleUsesTheConfiguredDecoder() async throws {
    let capture = try Self.secondsCapture(body: #"[{"id":1,"starts_at":1000}]"#)
    let row = try await capture.client.from(Event.self).select().maybeSingle().execute().value
    #expect(row?.startsAt == Self.date)
  }

  @Test
  func insertUsesTheConfiguredEncoder() async throws {
    let capture = try Self.secondsCapture()
    try await capture.client.from(Event.self).insert(.init(startsAt: Self.date)).execute()
    #expect(capture.bodyString == #"{"starts_at":1000}"#)
  }

  @Test
  func insertReturningUsesTheConfiguredDecoder() async throws {
    let capture = try Self.secondsCapture(body: #"[{"id":1,"starts_at":1000}]"#)
    let rows = try await capture.client.from(Event.self)
      .insert(.init(startsAt: Self.date)).returning().execute().value
    #expect(rows.first?.startsAt == Self.date)
  }

  @Test
  func updateUsesTheConfiguredEncoder() async throws {
    let capture = try Self.secondsCapture()
    try await capture.client.from(Event.self)
      .update { $0.startsAt = Self.date }.where { $0.id.eq(1) }.execute()
    #expect(capture.bodyString == #"{"starts_at":1000}"#)
  }

  @Test
  func upsertUsesTheConfiguredEncoder() async throws {
    let capture = try Self.secondsCapture()
    try await capture.client.from(Event.self).upsert(.init(startsAt: Self.date)).execute()
    #expect(capture.bodyString == #"{"starts_at":1000}"#)
  }

  @Test
  func rpcUsesTheConfiguredCoders() async throws {
    let capture = try Self.secondsCapture(body: "2000")
    let result = try await capture.client.rpc(EventsAfter(after: Self.date)).execute().value
    #expect(capture.bodyString == #"{"after":1000}"#)
    #expect(result == Date(timeIntervalSince1970: 2_000))
  }

  @Test
  func aKeyStrategyDoesNotDropTheOtherSettings() async throws {
    let capture = try Self.secondsCapture(
      body: #"[{"id":1,"starts_at":1000}]"#, snakeCase: true)
    let rows = try await capture.client.from(Event.self)
      .insert(.init(startsAt: Self.date)).returning().execute().value
    #expect(capture.bodyString == #"{"starts_at":1000}"#)
    #expect(rows.first?.startsAt == Self.date)
  }

  @Test
  func theTypedCodersAreTheConfiguredOnesWithoutAKeyStrategy() throws {
    let configuration = try PostgrestClient.Configuration(
      url: URL(string: "https://example.supabase.co")!)
    #expect(configuration.typedEncoder === configuration.encoder)
    #expect(configuration.typedDecoder === configuration.decoder)
  }

  private static func snakeCaseCapture(body: String = "[]") throws -> QueryCapture {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try QueryCapture(body: body, encoder: encoder, decoder: decoder)
  }

  @Test
  func selectIgnoresTheKeyStrategyOfTheConfiguredDecoder() async throws {
    let capture = try Self.snakeCaseCapture(body: #"[{"id":1,"is_done":true}]"#)
    let rows = try await capture.client.from(Todo.self).select().execute().value
    // `.convertFromSnakeCase` would look for the key "isDone" and fail on "is_done".
    #expect(rows.first?.isDone == true)
  }

  @Test
  func insertIgnoresTheKeyStrategyOfTheConfiguredEncoder() async throws {
    let capture = try Self.snakeCaseCapture()
    try await capture.client.from(Todo.self).insert(.init(isDone: true)).execute()
    #expect(capture.bodyString == #"{"isDone":true}"#)
  }

  @Test
  func updateIgnoresTheKeyStrategyOfTheConfiguredEncoder() async throws {
    let capture = try Self.snakeCaseCapture()
    try await capture.client.from(Todo.self).update { $0.dueAt = 3 }.all().execute()
    #expect(capture.bodyString == #"{"dueAt":3}"#)
  }
}
