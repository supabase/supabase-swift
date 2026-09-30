//
//  PostgrestFilterBuilderTests.swift
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
  @Suite(.mockerSerialized)
  struct PostgrestFilterBuilderTests {
    let fixture = PostgrestQueryFixture()
    var url: URL { fixture.url }
    var sut: PostgrestClient { fixture.sut }

    @Test
    func notFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?select=*&status=not.eq.OFFLINE"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .not("status", operator: .eq, value: "OFFLINE")
        .execute()
    }

    @Test
    func orFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?or=(status.eq.OFFLINE,username.eq.test)&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .or("status.eq.OFFLINE,username.eq.test")
        .execute()
    }

    @Test
    func orFilterWithReferencedTable() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?messages.or=(public.eq.true,recipient_id.eq.1)&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .or("public.eq.true,recipient_id.eq.1", referencedTable: "messages")
        .execute()
    }

    @Test
    func containsFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?address=cs.%7B%22postcode%22:90210%7D&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .contains("address", value: ["postcode": 90210])
        .execute()
    }

    @Test
    func textSearchFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?description=fts(english).programmer&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .textSearch("description", query: "programmer", config: "english")
        .execute()
    }

    @Test
    func multipleFilters() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?age=gte.18&select=*&status=eq.active"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .gte("age", value: 18)
        .eq("status", value: "active")
        .execute()
    }

    @Test
    func likeFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?email=like.%25@example.com&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .like("email", pattern: "%@example.com")
        .execute()
    }

    @Test
    func iLikeFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?email=ilike.%25@EXAMPLE.COM&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .ilike("email", pattern: "%@EXAMPLE.COM")
        .execute()
    }

    @Test
    func isFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?deleted_at=is.NULL&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .is("deleted_at", value: nil)
        .execute()
    }

    @Test
    func inFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?select=*&status=in.(active,pending)"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .in("status", values: ["active", "pending"])
        .execute()
    }

    @Test
    func notInFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?select=*&status=not.in.(archived,deleted)"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .notIn("status", values: ["archived", "deleted"])
        .execute()
    }

    @Test
    func inFilterQuotesValuesWithReservedCharacters() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?select=*&tags=in.(%22a,b%22,%22c(d)%22,plain)"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .in("tags", values: ["a,b", "c(d)", "plain"])
        .execute()
    }

    @Test
    func containedByFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?roles=cd.%7Badmin,user%7D&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .containedBy("roles", value: ["admin", "user"])
        .execute()
    }

    @Test
    func rangeFilters() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?age_range=sl.%5B18,25)&fifth_range=adj.%5B55,65)&fourth_range=nxr.%5B45,55)&other_range=sr.%5B25,35)&select=*&third_range=nxl.%5B35,45)"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .rangeLt("age_range", range: "[18,25)")
        .rangeGt("other_range", range: "[25,35)")
        .rangeGte("third_range", range: "[35,45)")
        .rangeLte("fourth_range", range: "[45,55)")
        .rangeAdjacent("fifth_range", range: "[55,65)")
        .execute()
    }

    @Test
    func overlapsFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?schedule=ov.%7B9:00,17:00%7D&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .overlaps("schedule", value: ["9:00", "17:00"])
        .execute()
    }

    @Test
    func matchFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?role=eq.admin&select=*&status=eq.active"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .match(["status": "active", "role": "admin"])
        .execute()
    }

    @Test
    func filterEscapeHatch() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?created_at=gt.2023-01-01&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .filter("created_at", operator: "gt", value: "2023-01-01")
        .execute()
    }

    @Test
    func neqFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?select=*&status=neq.inactive"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .neq("status", value: "inactive")
        .execute()
    }

    @Test
    func gtFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?age=gt.21&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .gt("age", value: 21)
        .execute()
    }

    @Test
    func ltFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?age=lt.65&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .lt("age", value: 65)
        .execute()
    }

    @Test
    func lteFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?age=lte.65&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .lte("age", value: 65)
        .execute()
    }

    @Test
    func likeAllOfFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?name=like(all).%7B%25test%25,%25user%25%7D&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .likeAllOf("name", patterns: ["%test%", "%user%"])
        .execute()
    }

    @Test
    func likeAnyOfFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?name=like(any).%7B%25test%25,%25user%25%7D&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .likeAnyOf("name", patterns: ["%test%", "%user%"])
        .execute()
    }

    @Test
    func iLikeAllOfFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?name=ilike(all).%7B%25TEST%25,%25USER%25%7D&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .iLikeAllOf("name", patterns: ["%TEST%", "%USER%"])
        .execute()
    }

    @Test
    func iLikeAnyOfFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?name=ilike(any).%7B%25TEST%25,%25USER%25%7D&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .iLikeAnyOf("name", patterns: ["%TEST%", "%USER%"])
        .execute()
    }

    @Test
    func ftsFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?description=fts.programmer&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .fts("description", query: "programmer")
        .execute()
    }

    @Test
    func regexMatchFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?email=match.%5E.+@.+%5C..+$&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .match("email", pattern: "^.+@.+\\..+$")
        .execute()
    }

    @Test
    func regexImatchFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?name=imatch.%5Ejohn&select=*"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .imatch("name", pattern: "^john")
        .execute()
    }

    @Test
    func isDistinctFilter() async throws {
      Mock(
        url: url.appendingPathComponent("users"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: Data("[]".utf8)]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Accept: application/json" \
        	--header "Content-Type: application/json" \
        	--header "X-Client-Info: postgrest-swift/0.0.0" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/rest/v1/users?select=*&status=isdistinct.null"
        """#
      }
      .register()

      _ =
        try await sut
        .from("users")
        .select()
        .isDistinct("status", value: "null")
        .execute()
    }
  }
}
