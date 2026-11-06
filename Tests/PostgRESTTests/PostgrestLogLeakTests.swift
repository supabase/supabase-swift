import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import PostgREST

@Suite
struct PostgrestLogLeakTests {
  private let recorder = LogRecorder()

  @Test
  func aSecretInTheQueryNeverReachesTheLog() async throws {
    let sut = PostgrestClient(
      url: URL(string: "http://localhost:54321/rest/v1")!,
      logger: recorder.makeLogger(),
      http: .init(
        transport: ClosureTransport { _, _ in
          (HTTPTypes.HTTPResponse(status: .ok), HTTPBody(Data("[]".utf8)))
        })
    )

    try await sut.from("invites").select().eq("code", value: "pg-secret-1").execute()

    #expect(!recorder.entries.isEmpty)
    #expect(!recorder.entries.contains { $0.contains("pg-secret") })
  }
}
