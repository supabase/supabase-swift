//
//  PluginTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation
import Testing

@testable import PostgrestMacros

@Suite
struct PluginTests {
  @Test
  func macroModuleReExportsPostgREST() {
    let configuration = PostgrestClient.Configuration(url: URL(string: "https://example.com")!)
    #expect(configuration.schema == nil)
  }
}
