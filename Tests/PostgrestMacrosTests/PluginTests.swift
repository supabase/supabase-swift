//
//  PluginTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import Testing

@testable import PostgrestMacros

@Suite
struct PluginTests {
  @Test
  func macroModuleReExportsPostgREST() {
    // Compiles only if PostgrestMacros re-exports PostgREST, which is what lets a user write a
    // single `import PostgrestMacros`.
    #expect(PostgrestClient.Configuration.defaultHeaders["X-Client-Info"] != nil)
  }
}
