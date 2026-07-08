//
//  PostgrestErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/05/24.
//

import Foundation
import Helpers
import Testing

@Suite
struct PostgrestErrorTests {

  @Test
  func localizedErrorConformance() {
    let error = PostgrestError(message: "test error message")
    #expect(error.errorDescription == "test error message")
  }

}
