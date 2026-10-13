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
