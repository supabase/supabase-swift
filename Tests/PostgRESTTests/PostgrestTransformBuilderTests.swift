//
//  PostgrestTransformBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import Foundation
import Mocker
import PostgREST
import TestHelpers
import Testing

extension PostgrestMockerTests {
  struct PostgrestTransformBuilderTests {
    let fixture = PostgrestQueryFixture()
    var url: URL { fixture.url }
    var sut: PostgrestClient { fixture.sut }

    @Test
    func select() async throws {
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

    @Test
    func order() async throws {
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

      #expect(countries[0].name == "United States")
      #expect(countries[0].cities[0].name == "New York City")
    }

    @Test
    func multipleOrder() async throws {
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

    @Test
    func limit() async throws {
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

      #expect(countries[0].name == "United States")
    }

    @Test
    func range() async throws {
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

      #expect(countries[0].name == "United States")
    }

    @Test
    func rangeWithReferencedTable() async throws {
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

    @Test
    func single() async throws {
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

      #expect(country["name"] == "United States")
    }

    @Test
    func maybeSingle() async throws {
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
        .maybeSingle()
        .execute()
        .value as [String: String]

      #expect(country["name"] == "United States")
    }

    @Test
    func cSV() async throws {
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

      #expect(ids == ["1", "2", "3"])
    }

    @Test
    func geoJSON() async throws {
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

    @Test
    func explain() async throws {
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
        	--header "Accept: application/vnd.pgrst.plan+text; for=\"application/json\"; options=analyze|verbose;" \
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

      #expect(explain.contains("Aggregate"))
    }

    @Test
    func explainWithJSONFormat() async throws {
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
        	--header "Accept: application/vnd.pgrst.plan+json; for=\"application/json\"; options=analyze;" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/countries?select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("countries")
        .select()
        .explain(analyze: true, format: .json)
        .execute()
    }

    @Test
    func maxAffectedOnUpdate() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .patch: Data("[]".utf8)
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request PATCH \
        	--header "Accept: application/json" \
        	--header "Content-Length: 20" \
        	--header "Content-Type: application/json" \
        	--header "Prefer: return=representation,handling=strict,max-affected=1" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"username\":\"admin\"}" \
        	"http://localhost:54321/rest/v1/users?id=eq.1"
        """#
      }
      .register()

      try await sut
        .from("users")
        .update(["username": "admin"])
        .eq("id", value: 1)
        .maxAffected(1)
        .execute()
    }

    @Test
    func maxAffectedTwice() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .patch: Data("[]".utf8)
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request PATCH \
        	--header "Accept: application/json" \
        	--header "Content-Length: 20" \
        	--header "Content-Type: application/json" \
        	--header "Prefer: return=representation,handling=strict,max-affected=5" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"username\":\"admin\"}" \
        	"http://localhost:54321/rest/v1/users?id=eq.1"
        """#
      }
      .register()

      try await sut
        .from("users")
        .update(["username": "admin"])
        .eq("id", value: 1)
        .maxAffected(1)
        .maxAffected(5)
        .execute()
    }

    @Test
    func maxAffectedOnDelete() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .delete: Data("[]".utf8)
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request DELETE \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "Prefer: return=representation,handling=strict,max-affected=5" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?id=in.(1,2,3,4,5)"
        """#
      }
      .register()

      try await sut
        .from("users")
        .delete()
        .in("id", values: [1, 2, 3, 4, 5])
        .maxAffected(5)
        .execute()
    }

    @Test
    func maxAffectedOnRpc() async throws {
      Mock(
        url: url.appendingPathComponent("rpc/delete_users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .post: Data("[]".utf8)
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request POST \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "Prefer: handling=strict,max-affected=10" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/rpc/delete_users"
        """#
      }
      .register()

      try await sut
        .rpc("delete_users")
        .maxAffected(10)
        .execute()
    }

    @Test
    func maxAffectedOnSelect() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
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
        	--header "Prefer: handling=strict,max-affected=3" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?select=*"
        """#
      }
      .register()

      try await sut
        .from("users")
        .select()
        .maxAffected(3)
        .execute()
    }

    @Test
    func stripNulls() async throws {
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
        	--header "Prefer: return=stripped-nulls" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/countries?select=*"
        """#
      }
      .register()

      try await sut
        .from("countries")
        .select()
        .stripNulls()
        .execute()
    }

    @Test
    func stripNullsWithCSVThrowsError() async throws {
      do {
        try await sut
          .from("countries")
          .select()
          .csv()
          .stripNulls()
          .execute()
        Issue.record("Expected error to be thrown")
      } catch let error as PostgrestError {
        #expect(error.message == "`.stripNulls()` cannot be combined with `.csv()`")
      }
    }

    @Test
    func cSVWithStripNullsThrowsError() async throws {
      do {
        try await sut
          .from("countries")
          .select()
          .stripNulls()
          .csv()
          .execute()
        Issue.record("Expected error to be thrown")
      } catch let error as PostgrestError {
        #expect(error.message == "`.csv()` cannot be combined with `.stripNulls()`")
      }
    }

    @Test
    func dryRun() async throws {
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
        	--header "Prefer: tx=rollback" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/countries?select=*"
        """#
      }
      .register()

      try await sut
        .from("countries")
        .select()
        .dryRun()
        .execute()
    }

    @Test
    func dryRunOnUpdate() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [
          .patch: Data("[]".utf8)
        ]
      )
      .snapshotRequest {
        #"""
        curl \
        	--request PATCH \
        	--header "Accept: application/json" \
        	--header "Content-Length: 20" \
        	--header "Content-Type: application/json" \
        	--header "Prefer: return=representation,tx=rollback" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	--data "{\"username\":\"admin\"}" \
        	"http://localhost:54321/rest/v1/users?id=eq.1"
        """#
      }
      .register()

      try await sut
        .from("users")
        .update(["username": "admin"])
        .eq("id", value: 1)
        .dryRun()
        .execute()
    }
  }
}
