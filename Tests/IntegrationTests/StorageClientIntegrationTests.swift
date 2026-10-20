//
//  StorageClientIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 07/05/24.
//

import Foundation
import Helpers
import InlineSnapshotTesting
import Storage
import Supabase
import TestHelpers
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct StorageClientIntegrationTests {
  let storage = StorageIntegration.client()

  init() async throws {
    let testBucketName = "test-bucket"
    do {
      let files = try await storage.from(testBucketName).list()
      if !files.isEmpty {
        let filePaths = files.map { $0.name }
        try await storage.from(testBucketName).remove(paths: filePaths)
      }
      try await storage.deleteBucket(testBucketName)
    } catch {
    }
  }

  @Test
  func bucket_CRUD() async throws {
    let bucketName = "test-bucket"

    var buckets = try await storage.listBuckets()
    #expect(!buckets.contains(where: { $0.name == bucketName }))

    let created = try await storage.createBucket(bucketName, options: .init(isPublic: true))
    #expect(created == bucketName)

    var bucket = try await storage.bucket(bucketName)
    #expect(bucket.name == bucketName)
    #expect(bucket.id == bucketName)
    #expect(bucket.isPublic == true)

    buckets = try await storage.listBuckets()
    #expect(buckets.contains { $0.id == bucket.id })

    try await storage.updateBucket(
      bucketName, options: UpdateBucketOptions(allowedMimeTypes: ["image/jpeg"]))

    bucket = try await storage.bucket(bucketName)
    #expect(bucket.allowedMimeTypes == ["image/jpeg"])
    #expect(bucket.isPublic == true)

    try await storage.updateBucket(bucketName, options: UpdateBucketOptions(isPublic: false))

    bucket = try await storage.bucket(bucketName)
    #expect(bucket.isPublic == false)
    #expect(bucket.allowedMimeTypes == ["image/jpeg"])

    try await storage.deleteBucket(bucketName)

    buckets = try await storage.listBuckets()
    #expect(!buckets.contains { $0.id == bucket.id })
  }

  @Test
  func getBucketWithWrongId() async {
    do {
      _ = try await storage.bucket("not-exist-id")
      Issue.record("Unexpected success")
    } catch let error as StorageError {
      #expect(error.kind == .server)
      #expect(error.serverError?.error == "Bucket not found")
      #expect(error.serverError?.code == .noSuchBucket)
      #expect(error.message == "Bucket not found")
      #expect(error.serverStatusCode == 404)
      #expect(error.response != nil)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test(arguments: [
    (ByteCount.megabytes(1.5), Int64(1_500_000)),
    (.kilobytes(2), 2_000),
    ("3mb", 3_000_000),
    (4096, 4096),
  ])
  func fileSizeLimitRoundTrips(limit: ByteCount, bytes: Int64) async throws {
    let name = try await StorageIntegration.newBucket(
      "limit", options: CreateBucketOptions(isPublic: false, fileSizeLimit: limit))
    defer { StorageIntegration.dropBucket(name) }

    let bucket = try await storage.bucket(name)
    #expect(bucket.fileSizeLimit == bytes)
    #expect(bucket.isPublic == false)
  }

  @Test
  func createBucketAppliesEveryOptionAndReturnsTheName() async throws {
    let name = "full-\(UUID().uuidString.lowercased())"
    defer { StorageIntegration.dropBucket(name) }

    let created = try await storage.createBucket(
      name,
      options: CreateBucketOptions(
        isPublic: true, fileSizeLimit: .kilobytes(1), allowedMimeTypes: ["text/plain"]))
    #expect(created == name)

    let bucket = try await storage.bucket(name)
    #expect(bucket.id == name)
    #expect(bucket.isPublic == true)
    #expect(bucket.fileSizeLimit == 1_000)
    #expect(bucket.allowedMimeTypes == ["text/plain"])
    #expect(try await storage.listBuckets().contains { $0.id == name })

    let tooBig = await StorageIntegration.storageError {
      try await storage.from(name).upload(
        path: "big.txt", data: Data(repeating: 0x61, count: 2_048),
        options: UploadOptions(contentType: "text/plain"))
    }
    #expect(tooBig?.code == .entityTooLarge)
    #expect(tooBig?.serverStatusCode == 413)

    let wrongType = await StorageIntegration.storageError {
      try await storage.from(name).upload(
        path: "img.jpg", data: Data("x".utf8), options: UploadOptions(contentType: "image/jpeg"))
    }
    #expect(wrongType?.code == .invalidMimeType)
    #expect(wrongType?.serverStatusCode == 415)
  }

  @Test
  func partialUpdateChangesOnlyTheGivenFields() async throws {
    let name = try await StorageIntegration.newBucket(
      "partial", options: CreateBucketOptions(isPublic: true, allowedMimeTypes: ["text/plain"]))
    defer { StorageIntegration.dropBucket(name) }

    try await storage.updateBucket(
      name, options: UpdateBucketOptions(fileSizeLimit: .init(bytes: 10)))
    var bucket = try await storage.bucket(name)
    #expect(bucket.isPublic == true)
    #expect(bucket.allowedMimeTypes == ["text/plain"])
    #expect(bucket.fileSizeLimit == 10)

    let tooBig = await StorageIntegration.storageError {
      try await storage.from(name).upload(
        path: "big.txt", data: Data(repeating: 0x61, count: 11),
        options: UploadOptions(contentType: "text/plain"))
    }
    #expect(tooBig?.code == .entityTooLarge)

    try await storage.updateBucket(name, options: UpdateBucketOptions(isPublic: false))
    bucket = try await storage.bucket(name)
    #expect(bucket.isPublic == false)
    #expect(bucket.fileSizeLimit == 10)
  }

  @Test
  func emptyUpdateIsRefusedBeforeSending() async throws {
    let error = await StorageIntegration.storageError {
      try await storage.updateBucket("any", options: UpdateBucketOptions())
    }

    #expect(error?.kind == .invalidRequest)
    #expect(error?.response == nil)
  }

  @Test
  func duplicateBucketIsBucketAlreadyExists() async throws {
    let name = try await StorageIntegration.newBucket("dup")
    defer { StorageIntegration.dropBucket(name) }

    let error = await StorageIntegration.storageError {
      _ = try await storage.createBucket(name)
    }

    #expect(error?.code == .bucketAlreadyExists)
    #expect(error?.serverStatusCode == 409)
  }

  @Test
  func deletingANonEmptyBucketIsResourceNotEmpty() async throws {
    let name = try await StorageIntegration.newBucket("non-empty")
    defer { StorageIntegration.dropBucket(name) }
    try await storage.from(name).upload(path: "keep.txt", data: Data("keep".utf8))

    let error = await StorageIntegration.storageError {
      try await storage.deleteBucket(name)
    }

    #expect(error?.code == .resourceNotEmpty)
    #expect(error?.serverStatusCode == 409)
  }

  @Test
  func malformedBearerIsAccessDenied() async throws {
    let client = StorageIntegration.client(headers: [.authorization: "Bearer not-a-jwt"])

    let error = await StorageIntegration.storageError {
      _ = try await client.listBuckets()
    }

    #expect(error?.code == .accessDenied)
    #expect(error?.serverStatusCode == 403)
    #expect(error?.response?.statusCode == 400)
  }

  @Test
  func missingAuthorizationIsRefusedByTheServer() async throws {
    let client = StorageIntegration.client(headers: [:])

    let error = await StorageIntegration.storageError {
      _ = try await client.listBuckets()
    }

    #expect(error?.kind == .server)
    #expect((error?.response?.statusCode ?? 0) >= 400)
    #if os(macOS)
      #expect(error?.code == .invalidRequest)
      #expect(error?.serverStatusCode == 400)
    #endif
  }

  @Test
  func accessTokenMiddlewareAuthenticatesEveryRequest() async throws {
    let name = try await StorageIntegration.newBucket("token")
    defer { StorageIntegration.dropBucket(name) }
    try await StorageIntegration.admin.from(name).upload(path: "seed.txt", data: Data("seed".utf8))

    actor Calls {
      var count = 0
      func bump() { count += 1 }
    }
    let calls = Calls()
    let client = StorageIntegration.client(
      headers: [.init("apikey")!: DotEnv.supabasePublishableKey],
      middlewares: [
        AccessTokenMiddleware {
          await calls.bump()
          return DotEnv.supabaseSecretKey
        }
      ])

    #expect(try await client.from(name).list().map(\.name) == ["seed.txt"])
    try await client.from(name).upload(path: "via-middleware.txt", data: Data("m".utf8))
    #expect(try await client.from(name).exists(path: "via-middleware.txt"))
    #expect(await calls.count == 3)
  }

  @Test
  func nilTokenSendsNoBearer() async throws {
    let name = try await StorageIntegration.newBucket("anon")
    defer { StorageIntegration.dropBucket(name) }
    let client = StorageIntegration.client(
      headers: [.init("apikey")!: DotEnv.supabasePublishableKey],
      middlewares: [AccessTokenMiddleware { nil }])

    #expect(try await client.from(name).list().isEmpty)
    let error = await StorageIntegration.storageError {
      try await client.from(name).upload(path: "anon.txt", data: Data("a".utf8))
    }
    #expect(error?.code == .accessDenied)
  }

  @Test
  func staticAuthorizationWinsOverTheMiddleware() async throws {
    let client = StorageIntegration.client(
      headers: [.authorization: "Bearer not-a-jwt"],
      middlewares: [AccessTokenMiddleware { DotEnv.supabaseSecretKey }])

    let error = await StorageIntegration.storageError {
      _ = try await client.listBuckets()
    }
    #expect(error?.code == .accessDenied)
    #expect(error?.message == "Invalid Compact JWS")
  }

  @Test
  func setHeaderReturnsAClientThatSendsIt() async throws {
    let name = try await StorageIntegration.newBucket("header")
    defer { StorageIntegration.dropBucket(name) }
    try await StorageIntegration.admin.from(name).upload(path: "seed.txt", data: Data("seed".utf8))

    let anon = StorageIntegration.client(headers: [.init("apikey")!: DotEnv.supabasePublishableKey])
    let elevated = anon.setHeader(
      name: .authorization, value: "Bearer \(DotEnv.supabaseSecretKey)")

    #expect(try await elevated.from(name).list().map(\.name) == ["seed.txt"])
    #expect(try await anon.from(name).list().isEmpty)
  }

  @Test
  func supabaseClientWithTheSecretKeyBypassesRowLevelSecurity() async throws {
    let name = try await StorageIntegration.newBucket("supabase-client")
    defer { StorageIntegration.dropBucket(name) }
    let client = SupabaseClient(
      supabaseURL: URL(string: DotEnv.supabaseURL)!,
      supabaseKey: DotEnv.supabaseSecretKey,
      options: SupabaseClientOptions(auth: .init(storage: InMemoryLocalStorage())))

    let payload = Data("from SupabaseClient".utf8)
    try await client.storage.from(name).upload(path: "file.txt", data: payload)
    #expect(try await client.storage.from(name).download(path: "file.txt").data() == payload)
    #expect(try await client.storage.listBuckets().contains { $0.id == name })
  }

  @Test
  func supabaseClientWithANewFormatKeySendsNoBearer() async throws {
    let name = try await StorageIntegration.newBucket("publishable")
    defer { StorageIntegration.dropBucket(name) }
    let client = SupabaseClient(
      supabaseURL: URL(string: DotEnv.supabaseURL)!,
      supabaseKey: DotEnv.supabaseNewFormatPublishableKey,
      options: SupabaseClientOptions(auth: .init(storage: InMemoryLocalStorage())))

    #expect(try await client.storage.from(name).list().isEmpty)
    let error = await StorageIntegration.storageError {
      try await client.storage.from(name).upload(path: "anon.txt", data: Data("a".utf8))
    }
    #expect(error?.code == .accessDenied)
    #expect(error?.serverStatusCode == 403)
  }
}
