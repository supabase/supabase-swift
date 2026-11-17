//
//  PostgrestMaybeSingleIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 17/11/26.
//

import Foundation
@_spi(Experimental) import PostgrestMacros
import Testing

/// `maybeSingle()` must answer the same on the typed and untyped paths against a real PostgREST:
/// `nil` for no row, the row for one, and PostgREST's `PGRST116` for more than one.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestMaybeSingleIntegrationTests {
  let client = try! PostgrestClient(
    configuration: .init(
      url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
      headers: [.apikey: DotEnv.supabasePublishableKey]
    )
  )

  struct Title: Decodable {
    var title: String
  }

  @Test
  func noRowIsNilOnBothPaths() async throws {
    let typed = try await client.from(Discussions.self)
      .select(DiscussionTitle.self)
      .where { $0.id.eq(999) }
      .maybeSingle()
      .execute()
    let untyped: PostgrestResponse<Title?> = try await client.from("discussions")
      .select("title")
      .eq("id", value: 999)
      .maybeSingle()
      .execute()

    #expect(typed.value == nil)
    #expect(untyped.value == nil)
    #expect(typed.status == .ok)
    #expect(untyped.status == .ok)
  }

  @Test
  func oneRowIsTheRowOnBothPaths() async throws {
    let typed = try await client.from(Discussions.self)
      .select(DiscussionTitle.self)
      .where { $0.id.eq(1) }
      .maybeSingle()
      .execute()
      .value
    let untyped: Title? = try await client.from("discussions")
      .select("title")
      .eq("id", value: 1)
      .maybeSingle()
      .execute()
      .value

    #expect(typed != nil)
    #expect(typed?.title == untyped?.title)
  }

  @Test
  func moreThanOneRowThrowsPGRST116OnBothPaths() async throws {
    let typed = await #expect(throws: PostgrestError.self) {
      _ = try await client.from(Discussions.self)
        .select(DiscussionTitle.self)
        .maybeSingle()
        .execute()
    }
    let untyped = await #expect(throws: PostgrestError.self) {
      let _: Title? = try await client.from("discussions")
        .select("title")
        .maybeSingle()
        .execute()
        .value
    }
    let server = await #expect(throws: PostgrestError.self) {
      let _: Title = try await client.from("discussions")
        .select("title")
        .single()
        .execute()
        .value
    }

    for error in [typed, untyped] {
      #expect(error?.kind == .server)
      #expect(error?.code == "PGRST116")
      #expect(error?.response?.status == server?.response?.status)
      #expect(error?.serverError == server?.serverError)
    }
  }
}
