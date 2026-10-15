//
//  StorageIntegrationHelpers.swift
//
//
//  Created by Guilherme Souza on 13/10/26.
//

import Foundation
import Helpers
import Storage
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// What the Storage integration suites share: the client under test, buckets, fixtures and the
/// two ways of looking at a result, the thrown `StorageError` and a plain HTTP fetch of a URL.
enum StorageIntegration {
  static let url = URL(string: "\(DotEnv.supabaseURL)/storage/v1")!

  static func client(
    headers: HTTPFields = [.authorization: "Bearer \(DotEnv.supabaseSecretKey)"],
    middlewares: [any ClientMiddleware] = []
  ) -> StorageClient {
    StorageClient(
      configuration: StorageClientConfiguration(
        url: url,
        headers: headers,
        http: HTTPClientConfiguration(middlewares: middlewares)
      ))
  }

  /// Whether `scripts/enable-storage-test-features.sh` turned on object lifecycles, analytics
  /// buckets and the CDN purge stub. Only the Docker stack can; the native one refuses those calls.
  static let hasTestFeatures = ProcessInfo.processInfo.environment["STORAGE_TEST_FEATURES"] != nil

  /// A purge Storage forwarded to the CDN purge stub.
  struct ForwardedPurge: Decodable, Equatable {
    struct Body: Decodable, Equatable {
      var type: String
      var bucketId: String?
      var objectName: String?
    }
    var path: String
    var body: Body
  }

  /// The purges Storage forwarded to the CDN purge stub, oldest first.
  static func forwardedPurges() async throws -> [ForwardedPurge] {
    let (data, _) = try await fetch(URL(string: "http://127.0.0.1:54329/requests")!)
    return try JSONDecoder().decode([ForwardedPurge].self, from: data)
  }

  static func clearForwardedPurges() async throws {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:54329/requests")!)
    request.httpMethod = "DELETE"
    _ = try await URLSession.shared.data(for: request)
  }

  /// The service-role client every suite uses to set up and tear down.
  static let admin = client()

  static func newBucket(
    _ prefix: String, options: BucketOptions = BucketOptions(isPublic: true)
  ) async throws -> String {
    let name = "\(prefix)-\(UUID().uuidString.lowercased())"
    _ = try await admin.createBucket(name, options: options)
    return name
  }

  /// Async cleanup can outlive the test if the process exits right after; fine for a local stack.
  static func dropBucket(_ name: String) {
    Task {
      try? await admin.emptyBucket(name)
      try? await admin.deleteBucket(name)
    }
  }

  static func fixtureURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/Upload")
      .appendingPathComponent(name)
  }

  /// Runs `body` and returns the `StorageError` it throws, recording an issue otherwise.
  static func storageError(
    _ body: () async throws -> Void, sourceLocation: SourceLocation = #_sourceLocation
  ) async -> StorageError? {
    do {
      try await body()
      Issue.record("Expected a StorageError", sourceLocation: sourceLocation)
    } catch let error as StorageError {
      return error
    } catch {
      Issue.record("Unexpected error \(error)", sourceLocation: sourceLocation)
    }
    return nil
  }

  static func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await URLSession.shared.data(from: url)
    return (data, try #require(response as? HTTPURLResponse))
  }
}

extension String {
  /// The key as it travels in a URL path: every segment percent-encoded the way `ObjectKey` does.
  var percentEncodedKey: String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~!$&'()*,;=:@")
    return split(separator: "/")
      .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
      .joined(separator: "/")
  }
}
