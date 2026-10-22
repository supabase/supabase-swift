//
//  PostgrestRawQueryTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 02/10/26.
//

import Foundation
import Testing

@_spi(Experimental) @testable import PostgREST

@Suite
struct PostgrestRawQueryTests {
  struct Todo: _PostgrestRelation {
    static let relationName = "todos"
    static let selectString = "*"

    var id: Int

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
    }

    static let columns = Columns()
  }

  func compileTimeFixture(_ query: _PostgrestQuery<Todo, [Todo]>) {
    let raw: _PostgrestRawQuery = query.csv()
    _ = raw
  }

  @Test
  func csvAsksForCSVAndReturnsTheText() async throws {
    let capture = QueryCapture(body: "id\n1\n")
    let csv = try await capture.client.from(Todo.self).select().csv().execute().value
    #expect(csv == "id\n1\n")
    #expect(capture.header("Accept") == "text/csv")
  }

  @Test
  func stripNullsBeforeCSVIsNotSent() async throws {
    let capture = QueryCapture(body: "id\n1\n")
    _ = try await capture.client.from(Todo.self).select().stripNulls().csv().execute()
    #expect(capture.header("Accept") == "text/csv")
  }

  @Test
  func geojsonAsksForGeoJSON() async throws {
    let capture = QueryCapture(body: "{}")
    _ = try await capture.client.from(Todo.self).select().geojson().execute()
    #expect(capture.header("Accept") == "application/geo+json")
  }

  @Test
  func explainPlansTheMediaTypeTheQueryWouldHaveAskedFor() async throws {
    let capture = QueryCapture(body: "plan")
    _ = try await capture.client.from(Todo.self).select().single()
      .explain(analyze: true, verbose: true, format: .json).execute()
    #expect(
      capture.header("Accept")
        == #"application/vnd.pgrst.plan+json; for="application/vnd.pgrst.object+json"; options=analyze|verbose;"#
    )
  }
}
