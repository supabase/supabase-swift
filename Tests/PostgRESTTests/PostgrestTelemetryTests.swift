//
//  PostgrestTelemetryTests.swift
//  PostgREST
//
//  Created by Guilherme Souza on 24/11/26.
//

import Foundation
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import PostgREST

@Suite
struct PostgrestTelemetryTests {
  private func redacted(_ string: String) -> String {
    PostgrestTelemetry.redactedURL(URL(string: string)!)
  }

  @Test
  func redactsFilterValuesAndKeepsTheShapingKeys() {
    #expect(
      redacted(
        "https://example.supabase.co/rest/v1/users?select=id,email&email=eq.john@doe.com&order=created_at.desc&limit=10&offset=20"
      )
        == "https://example.supabase.co/rest/v1/users?select=id,email&email=REDACTED&order=created_at.desc&limit=10&offset=20"
    )
  }

  @Test
  func redactsEachRepeatedKeyAndEmbeddedShapingKeys() {
    #expect(
      redacted(
        "https://example.supabase.co/rest/v1/users?age=gt.18&age=lt.65&posts.order=id&posts.limit=1"
      )
        == "https://example.supabase.co/rest/v1/users?age=REDACTED&age=REDACTED&posts.order=REDACTED&posts.limit=REDACTED"
    )
  }

  @Test
  func keysMatchCaseSensitively() {
    #expect(
      redacted("https://example.supabase.co/rest/v1/users?Select=secret")
        == "https://example.supabase.co/rest/v1/users?Select=REDACTED")
  }

  @Test
  func keepsPercentEncodedValuesAsSent() {
    #expect(
      redacted("https://example.supabase.co/rest/v1/users?select=id%2Cname&name=eq.a%26b")
        == "https://example.supabase.co/rest/v1/users?select=id%2Cname&name=REDACTED")
  }

  @Test
  func dropsUserInfoAndFragment() {
    #expect(
      redacted("https://user:secret@example.supabase.co:8443/rest/v1/users?id=eq.1#top")
        == "https://example.supabase.co:8443/rest/v1/users?id=REDACTED")
  }

  @Test
  func leavesAURLWithoutAQueryAlone() {
    #expect(
      redacted("https://example.supabase.co/rest/v1/users")
        == "https://example.supabase.co/rest/v1/users")
    #expect(
      redacted("https://example.supabase.co/rest/v1/users?")
        == "https://example.supabase.co/rest/v1/users")
  }

  @Test
  func redactsAKeyWithAnEmptyValueAndKeepsABareKey() {
    #expect(
      redacted("https://example.supabase.co/rest/v1/users?name=&flag")
        == "https://example.supabase.co/rest/v1/users?name=REDACTED&flag")
  }

  struct SomeFailure: Error {}

  @Test
  func namesAURLErrorByItsType() {
    let urlError = URLError(.notConnectedToInternet)
    #expect(PostgrestTelemetry.errorType(of: urlError) == String(reflecting: URLError.self))
    #if canImport(Darwin)
      #expect(
        PostgrestTelemetry.errorType(of: urlError as NSError) == String(reflecting: URLError.self))
    #endif
  }

  @Test
  func namesOtherErrorsByTheirQualifiedType() {
    #expect(PostgrestTelemetry.errorType(of: CancellationError()) == "Swift.CancellationError")
    #expect(
      PostgrestTelemetry.errorType(of: SomeFailure())
        == "PostgRESTTests.PostgrestTelemetryTests.SomeFailure")
  }
}
