//
//  StorageIntegrationHelpers.swift
//
//
//  Created by Guilherme Souza on 13/10/26.
//

import ConcurrencyExtras
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
    _ prefix: String, options: CreateBucketOptions = CreateBucketOptions(isPublic: true)
  ) async throws -> String {
    await finishPendingDrops()
    let name = "\(prefix)-\(UUID().uuidString.lowercased())"
    _ = try await admin.createBucket(name, options: options)
    return name
  }

  /// Drops still running from earlier tests.
  ///
  /// Storage's file backend removes empty folders up to its root after each delete, without a
  /// lock against uploads. When a drop deletes the last object on the stack while another test
  /// uploads, the upload's `mkdir` loses its parent and fails with "no such file or directory".
  /// So each new bucket waits for earlier drops to finish.
  private static let pendingDrops = LockIsolated<[Task<Void, Never>]>([])

  static func finishPendingDrops() async {
    let drops = pendingDrops.withValue { drops in
      defer { drops = [] }
      return drops
    }
    for drop in drops { await drop.value }
  }

  /// Async cleanup can outlive the test if the process exits right after; fine for a local stack.
  static func dropBucket(_ name: String) {
    let drop = Task {
      try? await admin.emptyBucket(name)
      try? await admin.deleteBucket(name)
    }
    pendingDrops.withValue { $0.append(drop) }
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

  /// The folders and object keys one level under `prefix`, across every page.
  static func level(_ bucket: StorageBucket, prefix: String = "") async throws
    -> (folders: [String], objects: [String])
  {
    var folders: [String] = []
    var objects: [String] = []
    for try await page in bucket.objects(prefix: prefix).pages {
      folders += page.folders
      objects += page.objects.map(\.name)
    }
    return (folders, objects)
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
