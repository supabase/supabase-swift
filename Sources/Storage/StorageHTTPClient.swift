import Foundation

public struct StorageHTTPSession: Sendable {
  public var fetch: @Sendable (_ request: URLRequest) async throws -> (Data, URLResponse)
  public var upload:
    @Sendable (_ request: URLRequest, _ data: Data) async throws -> (Data, URLResponse)

  public init(
    fetch: @escaping @Sendable (_ request: URLRequest) async throws -> (Data, URLResponse),
    upload: @escaping @Sendable (_ request: URLRequest, _ data: Data) async throws -> (
      Data, URLResponse
    )
  ) {
    self.fetch = fetch
    self.upload = upload
  }

  public init(session: URLSession = .shared) {
    self.init(
      fetch: { try await session.data(for: $0) },
      upload: { try await session.upload(for: $0, from: $1) }
    )
  }
}
