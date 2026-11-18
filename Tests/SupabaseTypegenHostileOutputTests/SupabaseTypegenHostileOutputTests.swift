//
//  SupabaseTypegenHostileOutputTests.swift
//  SupabaseTypegenHostileOutputTests
//
//  Created by Guilherme Souza on 17/11/26.
//

import PostgrestMacros
import Testing

@Suite
struct SupabaseTypegenHostileOutputTests {
  /// A database name reaches the generated code through the macros, so it must come back as the
  /// same string and never run as an interpolation.
  @Test
  func aHostileFunctionNameIsKeptAsData() {
    #expect(EvilFatalErrorNameFunction.functionName == #"evil\(fatalError())"name"#)
  }

  @Test
  func aHostileTableNameIsKeptAsData() {
    #expect(WeIrdName.relationName == #"we"ird\name"#)
  }
}
