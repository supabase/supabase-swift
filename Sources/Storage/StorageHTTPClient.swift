import Foundation
import HTTPTypes
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct StorageHTTPSession: Sendable {
  public var fetch:
    @Sendable (_ request: HTTPRequest, _ bodyData: Data?) async throws -> (Data, HTTPResponse)

  public init(
    fetch: @escaping @Sendable (_ request: HTTPRequest, _ bodyData: Data?) async throws -> (
      Data, HTTPResponse
    )
  ) {
    self.fetch = fetch
  }

  public init(session: URLSession = .shared) {
    self.init(
      fetch: { request, body in
        if let body {
          return try await session.upload(for: request, from: body)
        } else {
          return try await session.data(for: request)
        }
      }
    )
  }
}
