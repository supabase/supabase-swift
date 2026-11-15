//
//  SupabaseClientSwiftUITests.swift
//  Supabase
//
//  Created by Guilherme Souza on 14/11/26.
//

#if canImport(SwiftUI)
  import Foundation
  import SwiftUI
  import Testing

  @testable import Supabase

  @Suite
  struct SupabaseClientSwiftUITests {
    @Test
    func environmentReturnsTheClientItWasGiven() throws {
      let client = try SupabaseClient(
        supabaseURL: URL(string: "https://project.supabase.co")!,
        supabaseKey: "sb_publishable_key",
        configuration: .init(auth: .init(storage: InMemoryAuthStorage()))
      )
      var environment = EnvironmentValues()
      environment.supabase = client

      #expect(environment.supabase === client)
    }

    // `reportIssue` reaches `withKnownIssue` only on Darwin.
    #if canImport(Darwin)
      @Test
      func unsetEnvironmentReportsAnIssueAndFallsBackToLocalhost() throws {
        let environment = EnvironmentValues()

        var placeholder: SupabaseClient?
        withKnownIssue {
          placeholder = environment.supabase
        }
        let client = try #require(placeholder)

        #expect(client.supabaseURL == URL(string: "http://localhost:54321")!)
        #expect(client === environment.supabase)
      }
    #endif
  }
#endif
