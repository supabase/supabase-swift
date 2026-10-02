//
//  PostgrestRawQueryTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 02/10/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestRawQueryTests {
  struct Todo: PostgrestRelation {
    static let relationName = "todos"
    static let selectString = "*"

    var id: Int

    struct Columns: Sendable {
      let id = PostgrestColumn<Todo, Int>("id")
    }

    static let columns = Columns()
  }

  /// This fixture is documentation, not enforcement. Swift Testing cannot assert that code fails
  /// to compile, so nothing here fails if `stripNulls()` is ever added to `PostgrestRawQuery`.
  ///
  /// What it records: `csv()`, `geojson()` and `explain(…)` return `PostgrestRawQuery`, and that
  /// type has no `stripNulls()` and no way back to `PostgrestQuery`. So these lines do not compile:
  ///
  /// ```swift
  /// query.csv().stripNulls()        // value of type 'PostgrestRawQuery' has no member 'stripNulls'
  /// query.csv().where { $0.id.eq(1) }  // no member 'where'
  /// ```
  ///
  /// The other order, `query.stripNulls().csv()`, compiles. The strip is set on the query, not on
  /// the request, so `csv()` never carries it into the raw request. That is checked at runtime by
  /// `stripNullsBeforeCSVIsNotSent()` below.
  ///
  /// Paste either line into this function to see the compile error.
  func compileTimeFixture(_ query: PostgrestQuery<Todo, [Todo]>) {
    let raw: PostgrestRawQuery = query.csv()
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
