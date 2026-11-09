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
    let sut = try PostgrestClient(
      configuration: .init(
        url: URL(string: "http://localhost:54321/rest/v1")!,
        http: .init(
          transport: ClosureTransport { _, _ in
            (HTTPTypes.HTTPResponse(status: .ok), HTTPBody(Data("[]".utf8)))
          }),
        logger: recorder.makeLogger()
      )
    )

    try await sut.from("invites").select().eq("code", value: "pg-secret-1").execute()

    #expect(!recorder.entries.isEmpty)
    #expect(!recorder.entries.contains { $0.contains("pg-secret") })
  }
}
