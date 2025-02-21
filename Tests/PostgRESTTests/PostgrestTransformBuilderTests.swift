//
//  PostgrestTransformBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import Mocker
import PostgREST
import XCTest

#if !os(Windows) && !os(Linux) && !os(Android) // no URLSessionConfiguration.protocolClasses
final class PostgrestTransformBuilderTests: PostgrestQueryTests {

  func testSelect() async throws {
    Mock(
      url: url.appendingPathComponent("users"),
      ignoreQuery: true,
      statusCode: 201,
      data: [
        .post: Data(#"{"username":"admin""#.utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Accept: application/json" \
      	--header "Content-Length: 27" \
      	--header "Content-Type: application/json" \
      	--header "Prefer: return=representation" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"id\":1,\"username\":\"admin\"}" \
      	"http://localhost:54321/rest/v1/users?select=username,%22first%20name%22"
      """#
    }
    .register()

    try await sut
      .from("users")
      .insert(User(id: 1, username: "admin"), returning: .minimal)
      .select("username, \"first name\"")
      .execute()
  }

  func testOrder() async throws {
    Mock(
      url: url.appendingPathComponent("cities"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data(
          """
            [
                {
                  "name": "United States",
                  "cities": [
                    {
                      "name": "New York City"
                    },
                    {
                      "name": "Atlanta"
                    }
                  ]
                },
                {
                  "name": "Vanuatu",
                  "cities": []
                }
              ]
          """.utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/cities?countries.order=name.asc.nullslast&select=name,country:countries(name)"
      """#
    }
    .register()

    let countries =
      try await sut
      .from("cities")
      .select(
        """
        name,
        country:countries(
          name
        )
        """
      )
      .order("name", ascending: true, referencedTable: "countries")
      .execute()
      .value as [Country]

    XCTAssertEqual(countries[0].name, "United States")
    XCTAssertEqual(countries[0].cities[0].name, "New York City")
  }

  func testMultipleOrder() async throws {
    Mock(
      url: url.appendingPathComponent("cities"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data("[]".utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/cities?order=num_of_habitants.asc.nullslast,name.desc.nullsfirst&select=name,num_of_habitants"
      """#
    }
    .register()

    try await sut
      .from("cities")
      .select("name,num_of_habitants")
      .order("num_of_habitants")
      .order("name", ascending: false, nullsFirst: true)
      .execute()
  }

  func testLimit() async throws {
    Mock(
      url: url.appendingPathComponent("countries"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data(
          """
          [
            {
              "name": "United States",
              "cities": [
                {
                  "name": "Atlanta"
                }
              ]
            }
          ]
          """.utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/countries?cities.limit=1&select=name,cities(name)"
      """#
    }
    .register()

    let countries =
      try await sut
      .from("countries")
      .select(
        """
        name,
        cities (
          name
        )
        """
      )
      .limit(1, referencedTable: "cities")
      .execute()
      .value as [Country]

    XCTAssertEqual(countries[0].name, "United States")
  }

  func testRange() async throws {
    Mock(
      url: url.appendingPathComponent("countries"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data(
          """
          [
            {
              "name": "United States",
              "cities": [
                {
                  "name": "Atlanta"
                }
              ]
            }
          ]
          """.utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/countries?limit=2&offset=0&select=name,cities(name)"
      """#
    }
    .register()

    let countries =
      try await sut
      .from("countries")
      .select(
        """
        name,
        cities (
          name
        )
        """
      )
      .range(from: 0, to: 1)
      .execute()
      .value as [Country]

    XCTAssertEqual(countries[0].name, "United States")
  }

  func testRangeWithReferencedTable() async throws {
    Mock(
      url: url.appendingPathComponent("countries"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data("[]".utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/countries?cities.limit=2&cities.offset=0&select=name,cities(name)"
      """#
    }
    .register()

    try await sut
      .from("countries")
      .select(
        """
        name,
        cities (
          name
        )
        """
      )
      .range(from: 0, to: 1, referencedTable: "cities")
      .execute()
  }

  func testSingle() async throws {
    Mock(
      url: url.appendingPathComponent("countries"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data(
          """
          {
            "name": "United States"
          }
          """.utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/vnd.pgrst.object+json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/countries?limit=1&select=name"
      """#
    }
    .register()

    let country =
      try await sut
      .from("countries")
      .select("name")
      .limit(1)
      .single()
      .execute()
      .value as [String: String]

    XCTAssertEqual(country["name"], "United States")
  }

  func testCSV() async throws {
    Mock(
      url: url.appendingPathComponent("countries"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data("id,name\n1,Afghanistan\n2,Albania\n3,Algeria".utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: text/csv" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/countries?select=*"
      """#
    }
    .register()

    let csv =
      try await sut
      .from("countries")
      .select()
      .csv()
      .execute()
      .string()

    let ids =
      csv?
      .split(separator: "\n")
      .dropFirst()
      .map { $0.split(separator: ",").first! } ?? []

    XCTAssertEqual(ids, ["1", "2", "3"])
  }

  func testGeoJSON() async throws {
    Mock(
      url: url.appendingPathComponent("countries"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data("[]".utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/geo+json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/countries?select=area"
      """#
    }
    .register()

    try await sut
      .from("countries")
      .select("area")
      .geojson()
      .execute()
  }

  func testExplain() async throws {
    Mock(
      url: url.appendingPathComponent("countries"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data(
          """
          Aggregate  (cost=33.34..33.36 rows=1 width=112) (actual time=0.041..0.041 rows=1 loops=1)
            Output: NULL::bigint, count(ROW(countries.id, countries.name)), COALESCE(json_agg(ROW(countries.id, countries.name)), '[]'::json), NULLIF(current_setting('response.headers'::text, true), ''::text), NULLIF(current_setting('response.status'::text, true), ''::text)
            ->  Limit  (cost=0.00..18.33 rows=1000 width=40) (actual time=0.005..0.006 rows=3 loops=1)
                  Output: countries.id, countries.name
                  ->  Seq Scan on public.countries  (cost=0.00..22.00 rows=1200 width=40) (actual time=0.004..0.005 rows=3 loops=1)
                        Output: countries.id, countries.name
          Query Identifier: -4730654291623321173
          Planning Time: 0.407 ms
          Execution Time: 0.119 ms
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/vnd.pgrst.plan+\"text\"; for=application/json; options=analyze|verbose;" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/countries?select=*"
      """#
    }
    .register()

    let explain =
      try await sut
      .from("countries")
      .select()
      .explain(analyze: true, verbose: true)
      .execute()
      .string() ?? ""

    XCTAssertTrue(explain.contains("Aggregate"))
  }
}
#endif
