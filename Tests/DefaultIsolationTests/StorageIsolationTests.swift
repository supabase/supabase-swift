//
//  StorageIsolationTests.swift
//  DefaultIsolationTests
//
//  Created by Guilherme Souza on 05/11/26.
//

import Foundation
@_spi(Experimental) import Supabase

#if canImport(CoreTransferable)
  import CoreTransferable
  import UniformTypeIdentifiers
#endif

/// Calls every public async Storage API from the main actor, since this target compiles with
/// `.defaultIsolation(MainActor.self)`. Nothing here runs: if a call stops compiling, the build
/// fails. `scripts/check-isolation-coverage.sh` checks that each API has a call.
enum StorageIsolationTests {
  /// Arguments the calls below need. Nothing creates one: it only has to type-check.
  struct Inputs {
    var updateBucketOptions: UpdateBucketOptions
    var lifecycle: LifecycleConfiguration
    var objectVersions: [ObjectVersion]
    var body: HTTPBody
    var vectors: [VectorEntry]
    var queryVector: VectorData
    var distanceMetric: VectorDistanceMetric
  }

  static func buckets(_ storage: StorageClient, _ inputs: Inputs) async throws {
    _ = try await storage.listBuckets()
    _ = try await storage.listBuckets(options: BucketListOptions())
    _ = try await storage.bucket("bucket")
    _ = try await storage.createBucket("bucket")
    _ = try await storage.createBucket("bucket", options: CreateBucketOptions())
    try await storage.updateBucket("bucket", options: inputs.updateBucketOptions)
    try await storage.emptyBucket("bucket")
    try await storage.deleteBucket("bucket")
    _ = try await storage.lifecycle(forBucket: "bucket")
    _ = try await storage.setLifecycle(inputs.lifecycle, forBucket: "bucket")
    try await storage.deleteLifecycle(forBucket: "bucket")
    try await storage.purgeCache(bucket: "bucket")
    try await storage.purgeCache(bucket: nil, transformationsOnly: true)
  }

  static func objects(_ bucket: StorageBucket, _ inputs: Inputs) async throws {
    let fileURL = URL(fileURLWithPath: "/tmp/file")

    _ = try await bucket.upload(path: "key", data: Data())
    _ = try await bucket.upload(path: "key", fileURL: fileURL)
    _ = try await bucket.upload(path: "key", body: inputs.body)
    _ = try await bucket.upload(
      path: "key", data: Data(), options: UploadOptions(), progress: { _ in })
    _ = try await bucket.update(path: "key", data: Data())
    _ = try await bucket.update(path: "key", fileURL: fileURL)
    _ = try await bucket.update(path: "key", body: inputs.body)
    try await bucket.move(from: "a", to: "b")
    _ = try await bucket.copy(from: "a", to: "b")
    _ = try await bucket.createSignedURL(path: "key", expiresIn: .seconds(60))
    _ = try await bucket.createSignedURLs(paths: ["key"], expiresIn: .seconds(60))
    _ = try await bucket.remove(paths: ["key"])
    _ = try await bucket.remove(versions: inputs.objectVersions)
    _ = try await bucket.list()
    _ = try await bucket.list(path: "folder", options: ListOptions())
    let download = try await bucket.download(path: "key")
    _ = try await download.data()
    _ = try await download.data(upTo: 1024)
    try await download.write(to: fileURL)
    for try await chunk in download.body { _ = chunk }
    _ = try await bucket.info(path: "key")
    _ = try await bucket.exists(path: "key")
    try await bucket.purgeCache(path: "key")
    let signed = try await bucket.createSignedUploadURL(path: "key")
    _ = signed
    _ = try await bucket.uploadToSignedURL(path: "key", token: "token", data: Data())
    _ = try await bucket.uploadToSignedURL(path: "key", token: "token", fileURL: fileURL)
    _ = try await bucket.uploadToSignedURL(path: "key", token: "token", body: inputs.body)
  }

  #if canImport(CoreTransferable)
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
    static func transferable(_ bucket: StorageBucket, item: some Transferable) async throws {
      _ = try await bucket.upload(path: "key", item: item, contentType: .png)
    }
  #endif

  static func listings(_ bucket: StorageBucket) async throws {
    let listing = bucket.objects(prefix: "folder/")
    for try await object in listing { _ = object }
    _ = try await listing.page()
    _ = try await listing.page(after: "cursor")
    for try await page in listing.pages { _ = page }
    var iterator = listing.makeAsyncIterator()
    _ = try await iterator.next()
    var pages = listing.pages.makeAsyncIterator()
    _ = try await pages.next()
  }

  static func resumable(
    _ storage: StorageClient, _ bucket: StorageBucket
  ) async throws {
    let upload = try bucket.resumableUpload(path: "key", data: Data())
    _ = upload.id.rawValue
    try await upload.start()
    try await upload.resume()
    await upload.pause()
    await upload.cancel()
    _ = try await upload.result
    _ = await upload.status
    for await progress in upload.progress() { _ = progress }
    for await status in upload.statusChanges() { _ = status }

    _ = try await storage.resumableUploads.resumeAll()
  }

  static func vectors(_ storage: StorageClient, _ inputs: Inputs) async throws {
    let vectorsClient = storage.vectors
    try await vectorsClient.createBucket("vectors")
    _ = try await vectorsClient.bucket("vectors")
    try await vectorsClient.deleteBucket("vectors")
    for try await bucket in vectorsClient.listBuckets() { _ = bucket }

    let bucket = vectorsClient.from("vectors")
    try await bucket.createIndex("index", dimension: 3, distanceMetric: inputs.distanceMetric)
    _ = try await bucket.indexDetails("index")
    try await bucket.deleteIndex("index")
    for try await index in bucket.listIndexes() { _ = index }

    let index = bucket.index("index")
    try await index.putVectors(inputs.vectors)
    _ = try await index.vectors(keys: ["key"])
    _ = try await index.queryVectors(inputs.queryVector, topK: 3)
    try await index.deleteVectors(keys: ["key"])
    for try await vector in index.listVectors() { _ = vector }
  }

  static func analytics(_ storage: StorageClient) async throws {
    let analytics = storage.analytics
    _ = try await analytics.createBucket("analytics")
    _ = try await analytics.listBuckets()
    try await analytics.deleteBucket("analytics")
  }
}
