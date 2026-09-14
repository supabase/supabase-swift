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

/// The default auth storage key namespaces the stored session by project ref, so two projects in
/// the same app do not share a session.
///
/// A `supabaseURL` with no host is a construction-time programmer error and traps, so that case is
/// covered here at the derivation helper rather than by constructing a client.
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

  // `"".split(separator: ".")` is empty, so an empty host yields `nil` rather than reading past
  // the end of the array — which is what the old `host.split(separator: ".")[0]` did.
  @Test(arguments: ["https:///rest/v1", "mailto:someone@example.com"])
  func derivesNoStorageKeyWhenTheURLHasNoHost(url: String) throws {
    #expect(SupabaseClient.defaultStorageKey(for: try #require(URL(string: url))) == nil)
  }

  // `storage` is passed explicitly, and `options` is never omitted: on Linux and Android
  // `AuthOptions.init` has no default storage, and the two-argument `SupabaseClient.init` does
  // not exist there at all.
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
}
