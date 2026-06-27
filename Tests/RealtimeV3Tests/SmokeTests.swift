import Testing

@testable import RealtimeV3

@Suite struct SmokeTests {
  @Test func moduleImports() {
    #expect(Bool(true))
  }
}
