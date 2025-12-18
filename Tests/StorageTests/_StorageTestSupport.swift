import ConcurrencyExtras
import Foundation
import Mocker
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

enum StorageTestSupport {
  static let baseURL = URL(string: "https://example.supabase.co/storage/v1")!

  static func makeSession() -> URLSession {
    URLSession(configuration: .mocking())
  }

  static func makeClient(
    url: URL = baseURL,
    headers: [String: String] = [:],
    accessToken: (@Sendable () async throws -> String?)? = nil,
    useNewHostname: Bool = false
  ) -> SupabaseStorageClient {
    SupabaseStorageClient(
      configuration: StorageClientConfiguration(
        url: url,
        headers: headers,
        encoder: .defaultStorageEncoder,
        decoder: .defaultStorageDecoder,
        session: makeSession(),
        accessToken: accessToken,
        logger: nil,
        useNewHostname: useNewHostname
      )
    )
  }

  static func makeFileAPI(
    bucketId: String = "bucket",
    url: URL = baseURL,
    headers: [String: String] = [:],
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) -> StorageFileApi {
    makeClient(url: url, headers: headers, accessToken: accessToken).from(bucketId)
  }

  static func makeBucketAPI(
    url: URL = baseURL,
    headers: [String: String] = [:],
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) -> StorageBucketApi {
    StorageBucketApi(
      configuration: StorageClientConfiguration(
        url: url,
        headers: headers,
        encoder: .defaultStorageEncoder,
        decoder: .defaultStorageDecoder,
        session: makeSession(),
        accessToken: accessToken,
        logger: nil,
        useNewHostname: false
      )
    )
  }

  static func captureRequest(into box: LockIsolated<URLRequest?>) -> OnRequestHandler {
    OnRequestHandler(requestCallback: { request in
      box.withValue { $0 = request }
    })
  }

  static func captureRequests(into box: LockIsolated<[URLRequest]>) -> OnRequestHandler {
    OnRequestHandler(requestCallback: { request in
      box.withValue { $0.append(request) }
    })
  }

  static func requestBody(_ request: URLRequest) -> Data? {
    request.httpBody ?? request.httpBodyStream.map(readAllBytes(from:))
  }

  static func readAllBytes(from stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      if read > 0 {
        data.append(buffer, count: read)
      } else {
        break
      }
    }
    return data
  }

  static func urlComponents(_ request: URLRequest) throws -> URLComponents {
    let url = try #require(request.url)
    return try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
  }

  static func queryDictionary(_ request: URLRequest) throws -> [String: String] {
    let components = try urlComponents(request)
    return Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
  }

  static func jsonObject(_ data: Data) throws -> Any {
    try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
  }
}

extension URLSessionConfiguration {
  fileprivate static func mocking() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockingURLProtocol.self]
    return config
  }
}
