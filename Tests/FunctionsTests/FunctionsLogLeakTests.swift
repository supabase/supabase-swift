import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Functions

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct FunctionsLogLeakTests {
  private let recorder = LogRecorder()

  @Test
  func aSecretInTheQueryOrTheResponseNeverReachesTheLog() async throws {
    let sut = FunctionsClient(
      configuration: .init(
        url: URL(string: "http://localhost:54321/functions/v1")!,
        http: .init(
          transport: ClosureTransport { _, _ in
            (
              HTTPTypes.HTTPResponse(status: .ok),
              HTTPBody(Data(#"{"access_token":"fn-secret-2"}"#.utf8))
            )
          }),
        logger: recorder.makeLogger()))

    try await sut.invoke(
      "hello", options: .init(query: [URLQueryItem(name: "token", value: "fn-secret-1")]))

    #expect(!recorder.entries.isEmpty)
    #expect(!recorder.entries.contains { $0.contains("fn-secret") })
  }
}
