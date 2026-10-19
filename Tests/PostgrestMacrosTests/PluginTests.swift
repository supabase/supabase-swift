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
    #expect(PostgrestClient.Configuration.defaultHeaders["X-Client-Info"] != nil)
  }
}
