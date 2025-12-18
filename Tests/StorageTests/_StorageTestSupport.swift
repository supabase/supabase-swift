import ConcurrencyExtras
import Foundation
import Mocker
import TestHelpers
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
        session: makeSession(),
        accessToken: accessToken,
        encoder: StorageClientConfiguration.defaultEncoder,
        decoder: StorageClientConfiguration.defaultDecoder,
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
        session: makeSession(),
        accessToken: accessToken,
        encoder: StorageClientConfiguration.defaultEncoder,
        decoder: StorageClientConfiguration.defaultDecoder,
        logger: nil,
        useNewHostname: false
      )
    )
  }
}
