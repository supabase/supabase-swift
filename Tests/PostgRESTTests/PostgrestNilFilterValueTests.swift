//
//  PostgrestNilFilterValueTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 19/08/26.
//

import Testing

@testable import PostgREST

@Suite
struct PostgrestNilFilterValueTests {
  @Test
  func isNullSendsIsNull() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select().is("email", value: nil).execute()
    #expect(capture.query?.contains("email=is.null") == true)
  }

  @Test
  func notIsNullSendsNotIsNull() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select()
      .not("email", operator: .is, value: "null").execute()
    #expect(capture.query?.contains("email=not.is.null") == true)
  }

  @Test
  func presentValueStillUsesEq() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select().eq("email", value: "a@b.co").execute()
    #expect(capture.query?.contains("email=eq.a@b.co") == true)
  }

  @Test
  func arrayColumnStillAcceptsNullMembers() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from("users").select()
      .contains("tags", value: [Optional("a"), nil]).execute()
    #expect(capture.query?.contains("tags=cs.{a,NULL}") == true)
  }
}
