//
//  StorageBucketPathTests.swift
//  Storage
//
//  Created by Guilherme Souza on 09/10/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Storage

/// Every path-taking method on ``StorageBucket`` sends the normalized key: in the URL,
/// percent-encoded per segment, or in the JSON body, as the plain path.
@Suite
struct StorageBucketPathTests {
  /// One public method, with the body the stub answers and where the key is expected.
  struct Operation: Sendable, CustomTestStringConvertible {
    enum Placement: Sendable { case url, body }

    let name: String
    let placement: Placement
    let response: String
    let run: @Sendable (StorageBucket, String) async throws -> URL?

    var testDescription: String { name }
  }

  static let operations: [Operation] = [
    Operation(name: "upload", placement: .url, response: #"{"Id":"id","Key":"bucket/x"}"#) {
      try await $0.upload(path: $1, data: Data())
      return nil
    },
    Operation(name: "update", placement: .url, response: #"{"Id":"id","Key":"bucket/x"}"#) {
      try await $0.update(path: $1, data: Data())
      return nil
    },
    Operation(name: "uploadToSignedURL", placement: .url, response: #"{"Key":"bucket/x"}"#) {
      try await $0.uploadToSignedURL(path: $1, token: "t", data: Data())
      return nil
    },
    Operation(
      name: "createSignedUploadURL", placement: .url,
      response: #"{"url":"/object/upload/sign/bucket/x?token=t"}"#
    ) {
      _ = try await $0.createSignedUploadURL(path: $1)
      return nil
    },
    Operation(
      name: "createSignedURL", placement: .url,
      response: #"{"signedURL":"/object/sign/bucket/x?token=t"}"#
    ) {
      _ = try await $0.createSignedURL(path: $1, expiresIn: 60)
      return nil
    },
    Operation(name: "createSignedURLs", placement: .body, response: "[]") {
      _ = try await $0.createSignedURLs(paths: [$1], expiresIn: 60)
      return nil
    },
    Operation(name: "move", placement: .body, response: #"{"message":"ok"}"#) {
      try await $0.move(from: $1, to: $1)
      return nil
    },
    Operation(name: "copy", placement: .body, response: #"{"Key":"bucket/x"}"#) {
      try await $0.copy(from: $1, to: $1)
      return nil
    },
    Operation(name: "remove", placement: .body, response: "[]") {
      try await $0.remove(paths: [$1])
      return nil
    },
    Operation(name: "list", placement: .body, response: "[]") {
      _ = try await $0.list(path: $1)
      return nil
    },
    Operation(name: "download", placement: .url, response: "bytes") {
      try await $0.download(path: $1)
      return nil
    },
    Operation(
      name: "info", placement: .url, response: #"{"id":"id","version":"v","name":"x"}"#
    ) {
      _ = try await $0.info(path: $1)
      return nil
    },
    Operation(
      name: "exists", placement: .url, response: #"{"id":"id","version":"v","name":"x"}"#
    ) {
      _ = try await $0.exists(path: $1)
      return nil
    },
    Operation(name: "purgeCache", placement: .url, response: #"{"message":"ok"}"#) {
      try await $0.purgeCache(path: $1)
      return nil
    },
    Operation(name: "publicURL", placement: .url, response: "") {
      try $0.publicURL(path: $1)
    },
  ]

  private func makeSUT(
    response: String, requests: LockIsolated<[HTTPRequest]>, bodies: LockIsolated<[Data]>
  ) -> StorageBucket {
    StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "http://localhost:54321/storage/v1")!,
        headers: [:],
        http: .init(
          transport: ClosureTransport { request, body in
            requests.withValue { $0.append(request) }
            if let body {
              let data = try await Data(collecting: body, upTo: .max)
              bodies.withValue { $0.append(data) }
            }
            return (
              HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
              HTTPBody(Data(response.utf8))
            )
          })
      )
    ).from("bucket")
  }

  @Test(
    arguments: operations,
    [
      ("/folder//my file+#?%.png/", "folder/my file+#?%.png", "folder/my%20file%2B%23%3F%25.png"),
      ("café/文件.png", "café/文件.png", "caf%C3%A9/%E6%96%87%E4%BB%B6.png"),
    ]
  )
  func sendsTheNormalizedKey(
    operation: Operation, input: (raw: String, path: String, encoded: String)
  ) async throws {
    let requests = LockIsolated<[HTTPRequest]>([])
    let bodies = LockIsolated<[Data]>([])
    let bucket = makeSUT(response: operation.response, requests: requests, bodies: bodies)

    let url = try await operation.run(bucket, input.raw)

    switch operation.placement {
    case .url:
      let path = try #require(url?.path(percentEncoded: true) ?? requests.value.first?.path)
      #expect(path.hasPrefix("/storage/v1/"))
      #expect(path.contains("/bucket/\(input.encoded)"))
    case .body:
      let body = try #require(bodies.value.first)
      let json = String(decoding: body, as: UTF8.self)
      #expect(json.contains(input.path.replacingOccurrences(of: "/", with: "\\/")))
    }
  }

  @Test(arguments: operations.filter { $0.name != "list" }, ["", "/", "a/../b.png", "./a.png"])
  func refusesAnInvalidPathBeforeSending(operation: Operation, input: String) async {
    let requests = LockIsolated<[HTTPRequest]>([])
    let bodies = LockIsolated<[Data]>([])
    let bucket = makeSUT(response: operation.response, requests: requests, bodies: bodies)

    await #expect {
      try await operation.run(bucket, input)
    } throws: { error in
      (error as? StorageError)?.kind == .invalidRequest
    }
    #expect(requests.value.isEmpty)
  }

  @Test
  func listAcceptsTheEmptyPrefix() async throws {
    let requests = LockIsolated<[HTTPRequest]>([])
    let bodies = LockIsolated<[Data]>([])
    let bucket = makeSUT(response: "[]", requests: requests, bodies: bodies)

    _ = try await bucket.list(path: "/")

    let json = try String(decoding: #require(bodies.value.first), as: UTF8.self)
    #expect(json.contains(#""prefix":"""#))
  }

  @Test
  func bucketIdIsEncodedAsOneSegment() async throws {
    let requests = LockIsolated<[HTTPRequest]>([])
    let bodies = LockIsolated<[Data]>([])
    let bucket = StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "http://localhost:54321/storage/v1")!,
        headers: [:],
        http: .init(
          transport: ClosureTransport { request, _ in
            requests.withValue { $0.append(request) }
            return (HTTPResponse(status: .ok), HTTPBody(Data("bytes".utf8)))
          })
      )
    ).from("my bucket")

    _ = try await bucket.download(path: "a.png")

    #expect(requests.value.first?.path == "/storage/v1/object/my%20bucket/a.png")
  }
}
