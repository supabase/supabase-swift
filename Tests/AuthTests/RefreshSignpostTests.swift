import Testing

@testable import Auth

@Suite
struct RefreshSignpostTests {
  struct Failure: Error, Equatable {}

  @Test
  func intervalReturnsTheValueOfTheRefresh() async throws {
    let value = try await RefreshSignpost.interval { 42 }
    #expect(value == 42)
  }

  @Test
  func intervalRethrowsTheErrorOfTheRefresh() async {
    await #expect(throws: Failure.self) {
      try await RefreshSignpost.interval { throw Failure() }
    }
  }
}
