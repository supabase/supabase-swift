import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct StorageLogLeakTests {
  private let recorder = LogRecorder()

  private func makeSUT(
    transport:
      @escaping @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) throws -> StorageClient {
    try StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "http://localhost:54321/storage/v1")!,
        headers: [:],
        http: .init(transport: ClosureTransport(handler: transport)),
        logger: recorder.makeLogger(),
        retryEnabled: false))
  }

  @Test
  func aSignedUploadTokenNeverReachesTheLog() async throws {
    let sut = try makeSUT { _, _ in
      (HTTPTypes.HTTPResponse(status: .ok), HTTPBody(Data(#"{"Key":"bucket/file.txt"}"#.utf8)))
    }

    _ = try await sut.from("bucket")
      .uploadToSignedURL(path: "file.txt", token: "st-secret-1", data: Data("hello".utf8))

    #expect(!recorder.entries.isEmpty)
    #expect(!recorder.entries.contains { $0.contains("st-secret") })
  }

  @Test
  func aFailedSignedUploadLogsNoToken() async throws {
    let sut = try makeSUT { request, _ in
      throw URLError(
        .timedOut, userInfo: [NSURLErrorFailingURLStringErrorKey: request.url!.absoluteString])
    }

    _ = try? await sut.from("bucket")
      .uploadToSignedURL(path: "file.txt", token: "st-secret-1", data: Data("hello".utf8))

    #expect(!recorder.entries.isEmpty)
    #expect(!recorder.entries.contains { $0.contains("st-secret") })
  }

  @Test
  func aSignedURLInTheResponseNeverReachesTheLog() async throws {
    let sut = try makeSUT { _, _ in
      (
        HTTPTypes.HTTPResponse(status: .ok),
        HTTPBody(Data(#"{"signedURL":"/object/sign/bucket/file.txt?token=st-secret-2"}"#.utf8))
      )
    }

    _ = try await sut.from("bucket").createSignedURL(path: "file.txt", expiresIn: .seconds(60))

    #expect(!recorder.entries.isEmpty)
    #expect(!recorder.entries.contains { $0.contains("st-secret") })
  }
}
