//
//  SupabaseClientStorageKeyTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 09/09/26.
//

import Foundation
import Testing

@testable import Auth
@testable import Supabase

@Suite
struct SupabaseClientStorageKeyTests {
  @Test(
    arguments: [
      ("https://project-ref.supabase.co", "sb-project-ref-auth-token"),
      ("https://project-ref.supabase.co/rest/v1", "sb-project-ref-auth-token"),
      ("http://localhost:54321", "sb-localhost-auth-token"),
    ]
  )
  func derivesTheStorageKeyFromTheProjectRef(url: String, expected: String) throws {
    #expect(SupabaseClient.defaultStorageKey(for: try #require(URL(string: url))) == expected)
  }

  @Test(arguments: ["https:///rest/v1", "mailto:someone@example.com"])
  func derivesNoStorageKeyWhenTheURLHasNoHost(url: String) throws {
    #expect(SupabaseClient.defaultStorageKey(for: try #require(URL(string: url))) == nil)
  }

  @Test
  func honorsAnExplicitStorageKeyOverTheProjectRef() throws {
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "test-key",
      options: SupabaseClientOptions(
        auth: .init(storage: InMemoryAuthStorage(), storageKey: "my-key")
      )
    )

    #expect(client.auth.configuration.storageKey == "my-key")
  }

  @Test
  func usesTheDerivedKeyWhenNoneIsGiven() throws {
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "test-key",
      options: SupabaseClientOptions(auth: .init(storage: InMemoryAuthStorage()))
    )

    #expect(client.auth.configuration.storageKey == "sb-project-ref-auth-token")
  }

  @Test(arguments: [
    "project-ref", "https:///rest/v1", "//project-ref.supabase.co", "mailto:someone@example.com",
  ])
  func constructingAClientWithoutASchemeOrHostThrows(url: String) throws {
    let error = #expect(throws: SupabaseClientError.self) {
      try SupabaseClient(
        supabaseURL: try #require(URL(string: url)),
        supabaseKey: "anon-key",
        options: SupabaseClientOptions(auth: .init(storage: InMemoryAuthStorage()))
      )
    }
    #expect(error?.kind == .invalidConfiguration)
    #expect(error?.response == nil)
    #expect(error?.description.hasPrefix("SupabaseClientError(invalidConfiguration): ") == true)
  }
}
