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
  func honorsAnExplicitStorageKeyOverTheProjectRef() {
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "test-key",
      options: SupabaseClientOptions(
        auth: .init(storage: AuthLocalStorageMock(), storageKey: "my-key")
      )
    )

    #expect(client.auth.configuration.storageKey == "my-key")
  }

  @Test
  func usesTheDerivedKeyWhenNoneIsGiven() {
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "test-key",
      options: SupabaseClientOptions(auth: .init(storage: AuthLocalStorageMock()))
    )

    #expect(client.auth.configuration.storageKey == "sb-project-ref-auth-token")
  }

  #if os(macOS) || os(Linux)
    @Test
    func constructingAClientWithoutAHostTraps() async {
      await #expect(processExitsWith: .failure) {
        _ = SupabaseClient(
          supabaseURL: URL(string: "project-ref")!,
          supabaseKey: "anon-key",
          options: SupabaseClientOptions(auth: .init(storage: AuthLocalStorageMock()))
        )
      }
    }
  #endif
}
