import Foundation
import Testing

import Functions

@Suite
struct FunctionsErrorTests {
  @Test
  func localizedDescription_matches() {
    #expect(
      FunctionsError.relayError.localizedDescription == "Relay Error invoking the Edge Function"
    )
    #expect(
      FunctionsError.httpError(code: 412, data: Data()).localizedDescription
        == "Edge Function returned a non-2xx status code: 412"
    )
  }
}
