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

  @Test
  func decodesDetailsFromWireKey() throws {
    let json = """
      {
        "code": "23505",
        "details": "Key (id)=(1) already exists.",
        "hint": "Use a different id.",
        "message": "duplicate key value violates unique constraint \\"users_pkey\\""
      }
      """

    let error = try JSONDecoder().decode(PostgrestError.self, from: Data(json.utf8))

    #expect(error.details == "Key (id)=(1) already exists.")
    #expect(error.hint == "Use a different id.")
    #expect(error.code == "23505")
    #expect(error.message == "duplicate key value violates unique constraint \"users_pkey\"")
  }

}
